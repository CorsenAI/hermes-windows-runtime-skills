from __future__ import annotations

import json
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
ISSUE_FORM_ID = re.compile(r"^[A-Za-z0-9_-]+$")


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


def load_unique_yaml(path: Path) -> dict[str, Any]:
    data = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)
    if not isinstance(data, dict):
        raise ValueError("document must be a YAML mapping")
    return data


def validate_issue_form(path: Path) -> None:
    data = load_unique_yaml(path)
    for key in ("name", "description", "body"):
        if key not in data:
            raise ValueError(f"missing required key: {key}")
    if not all(
        isinstance(data[key], str) and data[key].strip()
        for key in ("name", "description")
    ):
        raise ValueError("name and description must be non-empty strings")
    if "title" in data and not isinstance(data["title"], str):
        raise ValueError("title must be a string when present")
    body = data["body"]
    if not isinstance(body, list) or not body:
        raise ValueError("body must be a non-empty list")
    ids: set[str] = set()
    for item in body:
        if not isinstance(item, dict):
            raise ValueError("body item must be a mapping")
        item_type = item.get("type")
        if not isinstance(item_type, str) or not item_type:
            raise ValueError("body item type must be a non-empty string")
        item_id = item.get("id")
        if item_id is not None:
            if not isinstance(item_id, str) or not ISSUE_FORM_ID.fullmatch(item_id):
                raise ValueError(f"invalid body item id: {item_id!r}")
            if item_id in ids:
                raise ValueError(f"duplicate body item id: {item_id!r}")
            ids.add(item_id)
        elif item_type != "markdown":
            raise ValueError("non-Markdown body item must have an id")
        if not isinstance(item.get("attributes"), dict):
            raise ValueError("body item attributes must be a mapping")


def validate_issue_config(path: Path) -> None:
    data = load_unique_yaml(path)
    if set(data) != {"blank_issues_enabled", "contact_links"}:
        raise ValueError("config must contain blank_issues_enabled and contact_links")
    if not isinstance(data["blank_issues_enabled"], bool):
        raise ValueError("blank_issues_enabled must be boolean")
    links = data["contact_links"]
    if not isinstance(links, list) or not links:
        raise ValueError("contact_links must be a non-empty list")
    expected_urls = [
        "https://github.com/CorsenAI/hermes-windows-runtime-skills/security/policy",
        "https://github.com/NousResearch/hermes-agent/issues",
    ]
    for link in links:
        if not isinstance(link, dict) or set(link) != {"name", "url", "about"}:
            raise ValueError("contact link must contain name, url, and about")
    if [link["url"] for link in links] != expected_urls:
        raise ValueError("contact links must use the expected repository destinations")


def construct_unique_json(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    mapping: dict[str, Any] = {}
    for key, value in pairs:
        if key in mapping:
            raise ValueError(f"duplicate JSON key: {key!r}")
        mapping[key] = value
    return mapping


def validate_skills_sh(path: Path) -> None:
    data = json.loads(
        path.read_text(encoding="utf-8"), object_pairs_hook=construct_unique_json
    )
    if not isinstance(data, dict):
        raise ValueError("document must be a JSON object")
    if set(data) != {"$schema", "notGrouped", "groupings"}:
        raise ValueError("unexpected root property")
    if data["$schema"] != "https://skills.sh/schemas/skills.sh.schema.json":
        raise ValueError("unexpected skills.sh schema URL")
    if data["notGrouped"] not in {"top", "bottom"}:
        raise ValueError("notGrouped must be top or bottom")
    groups = data["groupings"]
    if not isinstance(groups, list) or len(groups) != 1:
        raise ValueError("expected one category grouping")
    group = groups[0]
    if not isinstance(group, dict) or set(group) != {"title", "description", "skills"}:
        raise ValueError("grouping must contain title, description, and skills")
    if not all(
        isinstance(group[key], str) and group[key].strip()
        for key in ("title", "description")
    ):
        raise ValueError("grouping title and description must be non-empty strings")
    if len(group["title"]) > 120 or len(group["description"]) > 500:
        raise ValueError("grouping title or description exceeds the published schema")
    expected = ["windows-wsl-file-navigation", "windows-python-runtime"]
    if group["skills"] != expected:
        raise ValueError(f"grouping skills must equal {expected!r}")
    if any(len(skill) > 120 for skill in group["skills"]):
        raise ValueError("grouping skill name exceeds the published schema")


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
    try:
        json.loads('{"name":"first","name":"second"}', object_pairs_hook=construct_unique_json)
    except ValueError:
        pass
    else:
        print("duplicate JSON key rejection self-test failed", file=sys.stderr)
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
    issue_forms = [
        root / ".github/ISSUE_TEMPLATE/bug_report.yml",
        root / ".github/ISSUE_TEMPLATE/feature_request.yml",
    ]
    for path in issue_forms:
        try:
            validate_issue_form(path)
            print(f"PASS: {path.relative_to(root).as_posix()}")
        except Exception as exc:
            print(f"FAIL: {path.relative_to(root).as_posix()}: {exc}", file=sys.stderr)
            return 1
    config_path = root / ".github/ISSUE_TEMPLATE/config.yml"
    try:
        validate_issue_config(config_path)
        print(f"PASS: {config_path.relative_to(root).as_posix()}")
    except Exception as exc:
        print(f"FAIL: {config_path.relative_to(root).as_posix()}: {exc}", file=sys.stderr)
        return 1
    skills_sh_path = root / "skills.sh.json"
    try:
        validate_skills_sh(skills_sh_path)
        print(f"PASS: {skills_sh_path.relative_to(root).as_posix()}")
    except Exception as exc:
        print(f"FAIL: {skills_sh_path.relative_to(root).as_posix()}: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
