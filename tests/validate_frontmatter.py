from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(
    loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False
) -> dict[Any, Any]:
    mapping: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise ValueError(f"duplicate YAML key: {key!r}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_unique_mapping
)

SEMVER = re.compile(
    r"^(0|[1-9]\d*)\."
    r"(0|[1-9]\d*)\."
    r"(0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
EXPECTED_PLATFORMS = {"windows", "linux"}
EXPECTED_TOOLS = {"terminal", "search_files", "read_file"}


def is_semver(value: object) -> bool:
    if not isinstance(value, str) or not SEMVER.fullmatch(value):
        return False
    prerelease = value.split("+", 1)[0].partition("-")[2]
    return not (
        prerelease
        and any(
            part.isdigit() and len(part) > 1 and part.startswith("0")
            for part in prerelease.split(".")
        )
    )


def require_list_set(value: Any, expected: set[str], label: str) -> None:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ValueError(f"{label} must be a list of strings")
    if len(value) != len(set(value)):
        raise ValueError(f"{label} contains duplicates")
    if set(value) != expected:
        raise ValueError(f"{label} must equal {sorted(expected)!r}")


def parse_skill(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("frontmatter must start on line one")
    try:
        closing = lines.index("---", 1)
    except ValueError as exc:
        raise ValueError("frontmatter closing marker is missing") from exc
    if closing == 1:
        raise ValueError("frontmatter is empty")
    data = yaml.load("\n".join(lines[1:closing]), Loader=UniqueKeyLoader)
    if not isinstance(data, dict):
        raise ValueError("frontmatter must be a mapping")
    return data


def validate_skill(path: Path) -> None:
    data = parse_skill(path)
    slug = path.parent.name
    if not SLUG.fullmatch(slug):
        raise ValueError(f"invalid directory slug: {slug!r}")
    if data.get("name") != slug:
        raise ValueError("frontmatter name must match the directory slug")

    description = data.get("description")
    if not isinstance(description, str) or not description.endswith("."):
        raise ValueError("description must be one sentence ending with a period")
    if len(description) > 60:
        raise ValueError("description exceeds 60 characters")

    version = data.get("version")
    if not is_semver(version):
        raise ValueError("version must be a SemVer string")
    if data.get("author") != "CorsenAI" or data.get("license") != "MIT":
        raise ValueError("author or license mismatch")

    require_list_set(data.get("platforms"), EXPECTED_PLATFORMS, "platforms")
    metadata = data.get("metadata")
    hermes = metadata.get("hermes") if isinstance(metadata, dict) else None
    if not isinstance(hermes, dict):
        raise ValueError("metadata.hermes must be a mapping")
    require_list_set(hermes.get("requires_tools"), EXPECTED_TOOLS, "requires_tools")

    tags = hermes.get("tags")
    if not isinstance(tags, list) or not tags or len(tags) != len(set(tags)):
        raise ValueError("metadata.hermes.tags must be a non-empty unique list")
    if hermes.get("category") != "software-development":
        raise ValueError("metadata.hermes.category mismatch")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_frontmatter.py <repository-root>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    try:
        yaml.load("name: first\nname: second\n", Loader=UniqueKeyLoader)
    except ValueError:
        pass
    else:
        print("duplicate-key rejection self-test failed", file=sys.stderr)
        return 1
    if is_semver("1.0.0-01") or not is_semver("1.0.0-1"):
        print("SemVer prerelease self-test failed", file=sys.stderr)
        return 1
    paths = sorted(root.glob("skills/*/SKILL.md"))
    if len(paths) != 2:
        print(f"expected two skills, found {len(paths)}", file=sys.stderr)
        return 1
    names: set[str] = set()
    for path in paths:
        try:
            validate_skill(path)
            name = path.parent.name
            if name in names:
                raise ValueError(f"duplicate skill slug: {name}")
            names.add(name)
            print(f"PASS: {path.relative_to(root).as_posix()}")
        except Exception as exc:
            print(f"FAIL: {path.relative_to(root).as_posix()}: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
