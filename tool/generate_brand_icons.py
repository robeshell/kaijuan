#!/usr/bin/env python3
"""Generate per-brand app icons from 1024 masters.

Masters (drop your designs here):
  brands/icons/comic/master_1024.png
  brands/icons/book/master_1024.png

If a master is missing, a distinct placeholder is generated.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]

# (filename, pixel size)
IOS_SIZES = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

MAC_SIZES = [
    ("app_icon_16.png", 16),
    ("app_icon_32.png", 32),
    ("app_icon_64.png", 64),
    ("app_icon_128.png", 128),
    ("app_icon_256.png", 256),
    ("app_icon_512.png", 512),
    ("app_icon_1024.png", 1024),
]

ANDROID_MIPMAP = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

BRANDS = {
    "comic": {
        "letter": "C",
        "bg": (0xEA, 0x58, 0x0C, 255),  # ember
        "fg": (255, 255, 255, 255),
    },
    "book": {
        "letter": "B",
        "bg": (0x47, 0x55, 0x69, 255),  # slate
        "fg": (255, 255, 255, 255),
    },
}


def master_path(brand: str) -> Path:
    return ROOT / "brands" / "icons" / brand / "master_1024.png"


def ensure_master(brand: str) -> Image.Image:
    path = master_path(brand)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        img = Image.open(path).convert("RGBA")
        if img.size != (1024, 1024):
            img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
        return img
    # Placeholder until design masters arrive
    meta = BRANDS[brand]
    img = Image.new("RGBA", (1024, 1024), meta["bg"])
    draw = ImageDraw.Draw(img)
    # Soft inner panel
    margin = 96
    draw.rounded_rectangle(
        [margin, margin, 1024 - margin, 1024 - margin],
        radius=180,
        fill=(255, 255, 255, 36),
    )
    letter = meta["letter"]
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 520)
    except OSError:
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 520)
        except OSError:
            font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), letter, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(
        ((1024 - tw) / 2 - bbox[0], (1024 - th) / 2 - bbox[1] - 20),
        letter,
        font=font,
        fill=meta["fg"],
    )
    img.save(path)
    print(f"wrote placeholder master {path.relative_to(ROOT)}")
    return img


def resize(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.Resampling.LANCZOS)


def write_set(img: Image.Image, dest: Path, sizes: list[tuple[str, int]]) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for name, px in sizes:
        resize(img, px).save(dest / name, format="PNG")


def copy_ios_contents(src: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / "Contents.json", dest / "Contents.json")


def copy_mac_contents(src: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / "Contents.json", dest / "Contents.json")


def write_android(brand: str, img: Image.Image) -> None:
    base = ROOT / "android" / "app" / "src" / brand / "res"
    for folder, px in ANDROID_MIPMAP.items():
        d = base / folder
        d.mkdir(parents=True, exist_ok=True)
        resize(img, px).save(d / "ic_launcher.png", format="PNG")


def sync_default_from_comic() -> None:
    """Default AppIcon catalogs track comic for non-flavor / legacy builds."""
    for platform, sizes in (
        ("ios", IOS_SIZES),
        ("macos", MAC_SIZES),
    ):
        if platform == "ios":
            comic = ROOT / "ios/Runner/Assets.xcassets/AppIcon-comic.appiconset"
            default = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
            names = [n for n, _ in IOS_SIZES]
        else:
            comic = ROOT / "macos/Runner/Assets.xcassets/AppIcon-comic.appiconset"
            default = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
            names = [n for n, _ in MAC_SIZES]
        for name in names:
            src = comic / name
            if src.exists():
                shutil.copy2(src, default / name)


def patch_xcode_appicon_names() -> None:
    """Set ASSETCATALOG_COMPILER_APPICON_NAME per flavor config."""
    for rel in (
        "ios/Runner.xcodeproj/project.pbxproj",
        "macos/Runner.xcodeproj/project.pbxproj",
    ):
        path = ROOT / rel
        text = path.read_text()
        # Within each XCBuildConfiguration named *-comic / *-book that has
        # ASSETCATALOG_COMPILER_APPICON_NAME, set brand catalog.
        import re

        def fix_block(m: re.Match[str]) -> str:
            block = m.group(0)
            name = m.group(1)
            if name.endswith("-comic"):
                catalog = "AppIcon-comic"
            elif name.endswith("-book"):
                catalog = "AppIcon-book"
            else:
                return block
            if "ASSETCATALOG_COMPILER_APPICON_NAME" in block:
                block = re.sub(
                    r"ASSETCATALOG_COMPILER_APPICON_NAME = [^;]+;",
                    f"ASSETCATALOG_COMPILER_APPICON_NAME = {catalog};",
                    block,
                )
            return block

        text2 = re.sub(
            r"/\* ((?:Debug|Release|Profile)-(?:comic|book)) \*/ = \{.*?\n\t\t\};",
            fix_block,
            text,
            flags=re.DOTALL,
        )
        # Also plain Debug/Release/Profile Runner targets → comic default
        # only when they already have ASSETCATALOG and not flavor-suffixed
        path.write_text(text2)
        print(f"patched app icon names in {rel}")


def main() -> None:
    ios_src = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    mac_src = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"

    for brand in BRANDS:
        img = ensure_master(brand)

        # iOS
        ios_dest = ROOT / f"ios/Runner/Assets.xcassets/AppIcon-{brand}.appiconset"
        copy_ios_contents(ios_src, ios_dest)
        write_set(img, ios_dest, IOS_SIZES)

        # macOS
        mac_dest = ROOT / f"macos/Runner/Assets.xcassets/AppIcon-{brand}.appiconset"
        copy_mac_contents(mac_src, mac_dest)
        write_set(img, mac_dest, MAC_SIZES)

        # Android flavor source sets
        write_android(brand, img)
        print(f"generated icons for {brand}")

    sync_default_from_comic()
    patch_xcode_appicon_names()
    print("done. Replace brands/icons/*/master_1024.png and re-run this script.")


if __name__ == "__main__":
    main()
