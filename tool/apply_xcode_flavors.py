#!/usr/bin/env python3
"""Add comic/book Xcode build configurations for Flutter --flavor.

Idempotent. Updates ios/ and macos/ Runner.xcodeproj + shared schemes.
"""

from __future__ import annotations

import re
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FLAVORS = ("comic", "book")
MODES = ("Debug", "Release", "Profile")


def new_id() -> str:
    return uuid.uuid4().hex[:24].upper()


def duplicate_configs(pbx: str, platform: str) -> str:
    pattern = re.compile(
        r"(\t\t)([0-9A-F]{24}) /\* (Debug|Release|Profile) \*/ = \{\n"
        r"\t\t\tisa = XCBuildConfiguration;\n"
        r"(.*?)\n"
        r"\t\t\tname = (Debug|Release|Profile);\n"
        r"\t\t\};",
        re.DOTALL,
    )

    existing_names = set(
        re.findall(r"name = ((?:Debug|Release|Profile)-(?:comic|book));", pbx)
    )
    inserts: list[str] = []
    # (new_id, flavor_name like Debug-comic, base_mode Debug)
    clones: list[tuple[str, str, str]] = []

    for m in pattern.finditer(pbx):
        indent, _old_id, mode_a, body, mode_b = m.groups()
        if mode_a != mode_b:
            continue
        mode = mode_a
        for flavor in FLAVORS:
            name = f"{mode}-{flavor}"
            if name in existing_names:
                continue
            new_block_id = new_id()
            new_body = body

            if platform == "ios":
                new_body = re.sub(
                    r"PRODUCT_BUNDLE_IDENTIFIER = [^;]+;",
                    f"PRODUCT_BUNDLE_IDENTIFIER = com.kaijuan.{flavor};",
                    new_body,
                )
                # Prefer flavored xcconfig when a baseConfigurationReference exists
                # pointing at Debug/Release.xcconfig — leave as-is; Flutter also
                # injects FLUTTER_TARGET via CLI -t.
            elif platform == "macos":
                # Runner target configs use AppInfo.xcconfig; point book/comic
                # to Brand-*.xcconfig if present as a file ref named Brand-X.
                if "AppInfo.xcconfig" in new_body or "33E5194F232828860026EE4D" in new_body:
                    # Replace reference by name comment if we can find Brand file id
                    brand_ref = f"Brand-{flavor}.xcconfig"
                    # Keep AppInfo for comic if Brand not wired; inject overrides
                    new_body += (
                        f"\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.kaijuan.{flavor};"
                        f"\n\t\t\t\tPRODUCT_NAME = Kaika\\ {flavor.capitalize()};"
                    )
                    # Fix PRODUCT_NAME spacing - use proper names
                    if flavor == "comic":
                        new_body = re.sub(
                            r"PRODUCT_NAME = Kaika\\ Comic;",
                            "PRODUCT_NAME = \"Kaika Comic\";",
                            new_body,
                        )
                    # simpler: rewrite the injected lines properly after
                    pass

            # Clean rewrite of PRODUCT overrides for macos target-level settings
            if platform == "macos" and "INFOPLIST_FILE = Runner/Info.plist" in new_body:
                # strip any botched inject and set clean overrides
                new_body = re.sub(
                    r"\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = [^;]+;",
                    "",
                    new_body,
                )
                new_body = re.sub(
                    r"\n\t\t\t\tPRODUCT_NAME = [^;]+;",
                    "",
                    new_body,
                )
                display = "Kaika Comic" if flavor == "comic" else "Kaika Book"
                new_body += (
                    f"\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.kaijuan.{flavor};"
                    f'\n\t\t\t\tPRODUCT_NAME = "{display}";'
                )

            if platform == "ios" and "INFOPLIST_FILE = Runner/Info.plist" in new_body:
                display = "Kaika Comic" if flavor == "comic" else "Kaika Book"
                if "PRODUCT_DISPLAY_NAME" not in new_body:
                    new_body += f'\n\t\t\t\tPRODUCT_DISPLAY_NAME = "{display}";'

            new_block = (
                f"{indent}{new_block_id} /* {name} */ = {{\n"
                f"\t\t\tisa = XCBuildConfiguration;\n"
                f"{new_body}\n"
                f"\t\t\tname = {name};\n"
                f"\t\t}};"
            )
            inserts.append(new_block)
            clones.append((new_block_id, name, mode))
            existing_names.add(name)

    if not inserts:
        return pbx

    marker = "/* End XCBuildConfiguration section */"
    if marker not in pbx:
        raise SystemExit(f"{platform}: XCBuildConfiguration section end not found")
    pbx = pbx.replace(marker, "\n".join(inserts) + "\n" + marker)

    def expand_list(match: re.Match[str]) -> str:
        head, ids_block, tail = match.group(1), match.group(2), match.group(3)
        if "/* Debug */" not in ids_block or "/* Debug-comic */" in ids_block:
            return match.group(0)
        extra_lines = []
        for block_id, name, mode in clones:
            if f"/* {mode} */" not in ids_block:
                continue
            # Avoid adding project-level-only clones into wrong lists:
            # add all matching mode clones that were created from any block
            # with this mode — may add extras to Flutter Assemble lists (ok).
            extra_lines.append(f"\t\t\t\t{block_id} /* {name} */,")
        # Dedupe while preserving order
        seen: set[str] = set()
        uniq = []
        for line in extra_lines:
            if line in seen:
                continue
            seen.add(line)
            uniq.append(line)
        if not uniq:
            return match.group(0)
        return head + ids_block + "\n" + "\n".join(uniq) + tail

    list_pat = re.compile(
        r"(buildConfigurations = \(\n)(.*?)(\n\t\t\t\);)",
        re.DOTALL,
    )
    # Problem: clones list has multiple Debug-comic from different targets
    # with different ids. expand_list adds ALL Debug-* clones to every list
    # that has Debug — wrong (duplicates many IDs into each list).

    # Fix: only add clone IDs that were derived in the same "wave" — instead
    # track which clone ids came from which original config by storing
    # original_id mapping. Rebuild with better structure.

    return pbx  # temporary — will replace with better version below


def duplicate_configs_v2(pbx: str, platform: str) -> str:
    """Clone each plain Mode config into Mode-flavor; track parent list membership
    by only appending clone ids next to their parent's id in configuration lists.
    """
    if re.search(r"name = Debug-comic;", pbx):
        return pbx  # already applied

    pattern = re.compile(
        r"(\t\t)([0-9A-F]{24}) /\* (Debug|Release|Profile) \*/ = \{\n"
        r"\t\t\tisa = XCBuildConfiguration;\n"
        r"(.*?)\n"
        r"\t\t\tname = (Debug|Release|Profile);\n"
        r"\t\t\};",
        re.DOTALL,
    )

    inserts: list[str] = []
    # parent_id -> list of (clone_id, name)
    children: dict[str, list[tuple[str, str]]] = {}

    for m in pattern.finditer(pbx):
        indent, parent_id, mode_a, body, mode_b = m.groups()
        if mode_a != mode_b:
            continue
        mode = mode_a
        kids: list[tuple[str, str]] = []
        for flavor in FLAVORS:
            name = f"{mode}-{flavor}"
            clone_id = new_id()
            new_body = body
            display = "Kaika Comic" if flavor == "comic" else "Kaika Book"
            bundle = f"com.kaijuan.{flavor}"

            # Inject brand keys *inside* buildSettings (before its closing);}
            def inject_settings(body: str, extra: dict[str, str]) -> str:
                if "buildSettings = {" not in body:
                    return body
                lines = []
                for k, v in extra.items():
                    # strip existing key if present
                    body = re.sub(rf"\t\t\t\t{k} = [^;]+;\n", "", body)
                    lines.append(f"\t\t\t\t{k} = {v};")
                injection = "\n".join(lines) + "\n"
                # before the last closing of buildSettings in body
                idx = body.rfind("\t\t\t};")
                if idx == -1:
                    return body
                return body[:idx] + injection + body[idx:]

            if platform == "ios":
                new_body = re.sub(
                    r"PRODUCT_BUNDLE_IDENTIFIER = [^;]+;",
                    f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};",
                    new_body,
                )
                if "INFOPLIST_FILE = Runner/Info.plist" in new_body:
                    new_body = inject_settings(
                        new_body,
                        {
                            "PRODUCT_BUNDLE_IDENTIFIER": bundle,
                            "PRODUCT_DISPLAY_NAME": f'"{display}"',
                        },
                    )
            elif platform == "macos":
                if "INFOPLIST_FILE = Runner/Info.plist" in new_body:
                    new_body = inject_settings(
                        new_body,
                        {
                            "PRODUCT_BUNDLE_IDENTIFIER": bundle,
                            "PRODUCT_NAME": f'"{display}"',
                        },
                    )

            new_block = (
                f"{indent}{clone_id} /* {name} */ = {{\n"
                f"\t\t\tisa = XCBuildConfiguration;\n"
                f"{new_body}\n"
                f"\t\t\tname = {name};\n"
                f"\t\t}};"
            )
            inserts.append(new_block)
            kids.append((clone_id, name))
        children[parent_id] = kids

    if not inserts:
        return pbx

    marker = "/* End XCBuildConfiguration section */"
    pbx = pbx.replace(marker, "\n".join(inserts) + "\n" + marker)

    # Expand configuration lists: after each parent id line, insert children
    for parent_id, kids in children.items():
        # Match the list entry for parent
        entry_pat = re.compile(
            rf"(\t\t\t\t{parent_id} /\* (?:Debug|Release|Profile) \*/,\n)"
        )

        def repl(m: re.Match[str], kids=kids) -> str:
            extra = "".join(f"\t\t\t\t{cid} /* {name} */,\n" for cid, name in kids)
            return m.group(1) + extra

        pbx, n = entry_pat.subn(repl, pbx)
        if n == 0:
            print(f"warning: parent {parent_id} not found in configuration lists")

    return pbx


def write_scheme(flavor: str, platform: str) -> None:
    if platform == "ios":
        src = ROOT / "ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"
        dest = (
            ROOT
            / f"ios/Runner.xcodeproj/xcshareddata/xcschemes/{flavor}.xcscheme"
        )
    else:
        src = ROOT / "macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"
        dest = (
            ROOT
            / f"macos/Runner.xcodeproj/xcshareddata/xcschemes/{flavor}.xcscheme"
        )

    text = src.read_text()
    for mode in MODES:
        text = text.replace(
            f'buildConfiguration = "{mode}"',
            f'buildConfiguration = "{mode}-{flavor}"',
        )
    dest.write_text(text)
    print(f"wrote {dest.relative_to(ROOT)}")


def main() -> None:
    for platform, rel in (
        ("ios", "ios/Runner.xcodeproj/project.pbxproj"),
        ("macos", "macos/Runner.xcodeproj/project.pbxproj"),
    ):
        path = ROOT / rel
        original = path.read_text()
        updated = duplicate_configs_v2(original, platform)
        if updated != original:
            path.write_text(updated)
            print(f"updated {rel}")
        else:
            print(f"unchanged {rel}")

    for flavor in FLAVORS:
        write_scheme(flavor, "ios")
        write_scheme(flavor, "macos")

    print("Done.")


if __name__ == "__main__":
    main()
