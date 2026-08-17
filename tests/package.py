from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath


VERSION_RE = re.compile(r"(?m)^version: (?P<value>\S+)$")
FORBIDDEN_PARTS = {".git", ".env"}
ALLOWED_MODES = {"100644", "100755"}
FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)


def run_git(repo: Path, *args: str, text: bool = False) -> bytes | str:
    result = subprocess.run(
        ["git", "-C", os.fspath(repo), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
        encoding="utf-8" if text else None,
    )
    if result.returncode != 0:
        stderr = result.stderr if text else result.stderr.decode("utf-8", "replace")
        raise RuntimeError(f"git {' '.join(args)} failed: {stderr.strip()}")
    return result.stdout


def validate_relative_path(value: str) -> None:
    if "\\" in value:
        raise ValueError(f"backslash is forbidden in repository path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or any(
        part in {"", ".", ".."} for part in path.parts
    ):
        raise ValueError(f"unsafe repository path: {value!r}")
    lowered = [part.lower() for part in path.parts]
    if any(part in FORBIDDEN_PARTS or part.startswith(".env.") for part in lowered):
        raise ValueError(f"forbidden archive path: {value!r}")


def read_tree(repo: Path) -> list[tuple[str, str, str]]:
    raw = run_git(repo, "ls-tree", "-r", "-z", "--full-tree", "HEAD")
    assert isinstance(raw, bytes)
    entries: list[tuple[str, str, str]] = []
    for record in raw.split(b"\0"):
        if not record:
            continue
        header, separator, path_bytes = record.partition(b"\t")
        if not separator:
            raise ValueError("malformed git tree entry")
        mode_bytes, kind_bytes, object_bytes = header.split(b" ", 2)
        path = path_bytes.decode("utf-8", "strict")
        mode = mode_bytes.decode("ascii")
        kind = kind_bytes.decode("ascii")
        object_id = object_bytes.decode("ascii")
        validate_relative_path(path)
        if kind != "blob" or mode not in ALLOWED_MODES:
            raise ValueError(f"unsupported tree entry: {mode} {kind} {path}")
        entries.append((path, mode, object_id))
    entries.sort(key=lambda item: item[0].encode("utf-8"))
    if not entries:
        raise ValueError("repository tree is empty")
    return entries


def read_blob(repo: Path, object_id: str) -> bytes:
    data = run_git(repo, "cat-file", "blob", object_id)
    assert isinstance(data, bytes)
    return data


def release_version(repo: Path, entries: list[tuple[str, str, str]]) -> str:
    versions: set[str] = set()
    for path, _, object_id in entries:
        if path.startswith("skills/") and path.endswith("/SKILL.md"):
            text = read_blob(repo, object_id).decode("utf-8", "strict")
            match = VERSION_RE.search(text)
            if not match:
                raise ValueError(f"missing version in {path}")
            versions.add(match.group("value"))
    if len(versions) != 1:
        raise ValueError("all skills must share one release version")
    return versions.pop()


def write_archive(
    repo: Path,
    output: Path,
    prefix: str,
    entries: list[tuple[str, str, str]],
) -> None:
    with zipfile.ZipFile(
        output,
        mode="x",
        compression=zipfile.ZIP_STORED,
        allowZip64=False,
    ) as archive:
        archive.comment = b""
        for path, mode, object_id in entries:
            info = zipfile.ZipInfo(prefix + path, date_time=FIXED_ZIP_TIME)
            info.create_system = 3
            info.create_version = 20
            info.extract_version = 20
            info.reserved = 0
            info.flag_bits = 0
            info.volume = 0
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = int(mode, 8) << 16
            info.internal_attr = 0
            info.extra = b""
            info.comment = b""
            archive.writestr(info, read_blob(repo, object_id))


def verify_archive(
    repo: Path,
    archive_path: Path,
    prefix: str,
    entries: list[tuple[str, str, str]],
) -> None:
    expected = [prefix + path for path, _, _ in entries]
    with zipfile.ZipFile(archive_path, mode="r", allowZip64=False) as archive:
        if archive.comment:
            raise ValueError("archive comment must be empty")
        actual = archive.namelist()
        if actual != expected:
            raise ValueError("archive paths or ordering differ from the Git tree")
        for info, (_, mode, object_id) in zip(
            archive.infolist(), entries, strict=True
        ):
            if info.date_time != FIXED_ZIP_TIME:
                raise ValueError(f"non-canonical timestamp: {info.filename}")
            if info.compress_type != zipfile.ZIP_STORED:
                raise ValueError(f"non-canonical compression: {info.filename}")
            if info.extra or info.comment or info.flag_bits or info.internal_attr:
                raise ValueError(f"non-canonical ZIP metadata: {info.filename}")
            if info.create_version != 20 or info.extract_version != 20:
                raise ValueError(f"non-canonical ZIP version: {info.filename}")
            if info.create_system != 3 or (info.external_attr >> 16) != int(mode, 8):
                raise ValueError(f"non-canonical mode: {info.filename}")
            if archive.read(info) != read_blob(repo, object_id):
                raise ValueError(f"archive content mismatch: {info.filename}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a canonical release ZIP from Git blobs."
    )
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output-path", required=True)
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve()
    output = Path(args.output_path).resolve()
    if output.exists():
        raise FileExistsError("refusing to overwrite an existing archive")
    top_level_output = run_git(repo, "rev-parse", "--show-toplevel", text=True)
    assert isinstance(top_level_output, str)
    top_level = Path(top_level_output.strip()).resolve()
    if os.path.normcase(os.fspath(top_level)) != os.path.normcase(os.fspath(repo)):
        raise ValueError("repo root does not match the Git top-level directory")
    if run_git(repo, "status", "--porcelain=v1", "-z"):
        raise ValueError("repository must be clean before packaging HEAD")

    entries = read_tree(repo)
    version = release_version(repo, entries)
    expected_name = f"hermes-windows-runtime-skills-v{version}.zip"
    if output.name != expected_name:
        raise ValueError(f"archive name must be {expected_name}")
    output.parent.mkdir(parents=True, exist_ok=True)
    prefix = f"hermes-windows-runtime-skills-v{version}/"

    try:
        write_archive(repo, output, prefix, entries)
        verify_archive(repo, output, prefix, entries)
    except Exception:
        output.unlink(missing_ok=True)
        raise

    print(f"PASS: {output}")
    print(f"SHA256: {sha256(output)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
