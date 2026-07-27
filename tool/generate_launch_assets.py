#!/usr/bin/env python3
"""Bake 开卷 launch surfaces from the comic brand master.

Mirrors kaiting's launch pipeline:
  - mark-only splash glyph (accent on transparent)
  - Android 12+ branding strip + animated icon
  - pre-31 launch_lockup (mark + title + tagline)
  - iOS LaunchImage set

Fonts: PingFang SC (preferred) — never Latin-only faces for Chinese copy.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "brands" / "icons" / "comic" / "master_1024.png"

LAUNCH_TITLE = "开卷"
LAUNCH_TAGLINE = "读自己的书"
# Brand canvas + chrome text (kai-brand-design defaults)
LAUNCH_BG = (0xF7, 0xF9, 0xFC, 255)
TITLE_COLOR = (0x1C, 0x1C, 0x22, 255)
SUBTITLE_COLOR = (0x70, 0x70, 0x7A, 255)
# ember accent
ACCENT = (0xEA, 0x58, 0x0C)

_LAUNCH_TITLE_FACES: tuple[tuple[str, int], ...] = (
    (
        "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/"
        "86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc",
        8,
    ),
    (
        "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/"
        "86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc",
        4,
    ),
    ("/System/Library/Fonts/Hiragino Sans GB.ttc", 2),
    ("/System/Library/Fonts/STHeiti Medium.ttc", 0),
    ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", 0),
    ("/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc", 0),
    ("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", 0),
    ("C:/Windows/Fonts/msyhbd.ttc", 0),
    ("C:/Windows/Fonts/msyh.ttc", 0),
    ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", 0),
)

_LAUNCH_BODY_FACES: tuple[tuple[str, int], ...] = (
    (
        "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/"
        "86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc",
        0,
    ),
    ("/System/Library/Fonts/Hiragino Sans GB.ttc", 0),
    ("/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc", 0),
    ("/System/Library/Fonts/STHeiti Medium.ttc", 0),
    ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", 0),
    ("C:/Windows/Fonts/msyh.ttc", 0),
    ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", 0),
)


def smoothstep(low: float, high: float, values: np.ndarray) -> np.ndarray:
    values = np.clip((values - low) / (high - low), 0.0, 1.0)
    return values * values * (3.0 - 2.0 * values)


def _cjk_renderable(font: ImageFont.ImageFont, sample: str = "开") -> bool:
    try:
        mask = font.getmask(sample)
    except Exception:  # noqa: BLE001
        return False
    width, height = getattr(mask, "size", (0, 0))
    return width > 0 and height > 0 and sum(mask) > 0


def launch_font(size: int, *, weight: str = "regular") -> ImageFont.ImageFont:
    faces = _LAUNCH_TITLE_FACES if weight == "semibold" else _LAUNCH_BODY_FACES
    last_error: Exception | None = None
    for path, index in faces:
        if not Path(path).exists():
            continue
        try:
            font = ImageFont.truetype(path, size=size, index=index)
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            continue
        if _cjk_renderable(font):
            return font
        last_error = RuntimeError(f"{path}[{index}] missing CJK")
    raise RuntimeError(
        "CJK-capable font required for launch text"
        + (f" ({last_error})" if last_error else "")
    )


def contain(
    image: Image.Image, box: tuple[int, int], canvas: tuple[int, int]
) -> Image.Image:
    ratio = min(box[0] / image.width, box[1] / image.height)
    size = (round(image.width * ratio), round(image.height * ratio))
    resized = image.resize(size, Image.Resampling.LANCZOS)
    output = Image.new("RGBA", canvas, (0, 0, 0, 0))
    output.alpha_composite(
        resized,
        ((canvas[0] - resized.width) // 2, (canvas[1] - resized.height) // 2),
    )
    return output


def extract_mark() -> Image.Image:
    """Isolate the cream open-book mark from the comic master field."""
    if not MASTER.exists():
        raise FileNotFoundError(f"Missing comic master: {MASTER}")
    source = np.asarray(Image.open(MASTER).convert("RGBA"), dtype=np.float32)
    red, green, blue, source_alpha = np.moveaxis(source, -1, 0)
    whiteness = np.minimum(np.minimum(red, green), blue)
    neutrality = 255.0 - (np.maximum(np.maximum(red, green), blue) - whiteness)
    alpha = (
        smoothstep(142.0, 220.0, whiteness)
        * smoothstep(160.0, 230.0, neutrality)
        * (source_alpha / 255.0)
    )
    alpha = np.where(alpha < 0.12, 0.0, alpha)

    strong = alpha > 0.5
    if strong.any():
        ys_s, xs_s = np.where(strong)
        cy, cx = float(ys_s.mean()), float(xs_s.mean())
    else:
        cy = source.shape[0] / 2.0
        cx = source.shape[1] / 2.0
    yy, xx = np.ogrid[0 : source.shape[0], 0 : source.shape[1]]
    radius = max(source.shape[0], source.shape[1]) * 0.48
    alpha = np.where((yy - cy) ** 2 + (xx - cx) ** 2 <= radius**2, alpha, 0.0)

    ys, xs = np.where(alpha > 0.12)
    if not len(xs):
        raise RuntimeError("Could not isolate 开卷 mark from comic master")
    pad = 4
    left = max(0, int(xs.min()) - pad)
    top = max(0, int(ys.min()) - pad)
    right = min(source.shape[1], int(xs.max()) + pad + 1)
    bottom = min(source.shape[0], int(ys.max()) + pad + 1)
    alpha = alpha[top:bottom, left:right]
    # Solid accent mark for launch (matches kaiting monochrome-on-accent).
    h, w = alpha.shape
    rgba = np.zeros((h, w, 4), dtype=np.float32)
    rgba[..., 0] = ACCENT[0]
    rgba[..., 1] = ACCENT[1]
    rgba[..., 2] = ACCENT[2]
    rgba[..., 3] = alpha * 255.0
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")


def monochrome(mark: Image.Image, color: tuple[int, int, int]) -> Image.Image:
    result = Image.new("RGBA", mark.size, (*color, 0))
    result.putalpha(mark.getchannel("A"))
    return result


def launch_branding(scale: int) -> Image.Image:
    image = Image.new("RGBA", (200 * scale, 80 * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    title = launch_font(22 * scale, weight="semibold")
    body = launch_font(13 * scale, weight="regular")
    draw.text(
        (100 * scale, 24 * scale),
        LAUNCH_TITLE,
        anchor="mm",
        fill=TITLE_COLOR,
        font=title,
    )
    draw.text(
        (100 * scale, 54 * scale),
        LAUNCH_TAGLINE,
        anchor="mm",
        fill=SUBTITLE_COLOR,
        font=body,
    )
    return image


def launch_lockup(mark: Image.Image, scale: int) -> Image.Image:
    image = Image.new("RGBA", (288 * scale, 288 * scale), (0, 0, 0, 0))
    mark_layer = contain(
        mark, (104 * scale, 104 * scale), (144 * scale, 144 * scale)
    )
    image.alpha_composite(mark_layer, (72 * scale, 28 * scale))
    draw = ImageDraw.Draw(image)
    title = launch_font(24 * scale, weight="semibold")
    body = launch_font(14 * scale, weight="regular")
    draw.text(
        (144 * scale, 177 * scale),
        LAUNCH_TITLE,
        anchor="mm",
        fill=TITLE_COLOR,
        font=title,
    )
    draw.text(
        (144 * scale, 210 * scale),
        LAUNCH_TAGLINE,
        anchor="mm",
        fill=SUBTITLE_COLOR,
        font=body,
    )
    return image


def main() -> None:
    mark = extract_mark()
    launch_source = monochrome(mark, ACCENT)

    branding_dir = ROOT / "brands" / "launch"
    branding_dir.mkdir(parents=True, exist_ok=True)
    launch_mark = contain(launch_source, (176, 176), (256, 256))
    launch_mark.save(branding_dir / "launch_mark.png", optimize=True)

    # iOS LaunchImage
    ios_launch = ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    ios_launch.mkdir(parents=True, exist_ok=True)
    for filename, size in (
        ("LaunchImage.png", 144),
        ("LaunchImage@2x.png", 288),
        ("LaunchImage@3x.png", 432),
    ):
        launch_mark.resize((size, size), Image.Resampling.LANCZOS).save(
            ios_launch / filename, optimize=True
        )

    # macOS LaunchImage (optional catalog — create if present)
    macos_launch = (
        ROOT / "macos" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    )
    if macos_launch.exists() or True:
        macos_launch.mkdir(parents=True, exist_ok=True)
        for filename, size in (("LaunchImage.png", 144), ("LaunchImage@2x.png", 288)):
            launch_mark.resize((size, size), Image.Resampling.LANCZOS).save(
                macos_launch / filename, optimize=True
            )
        contents = macos_launch / "Contents.json"
        if not contents.exists():
            contents.write_text(
                """{
  "images" : [
    { "idiom" : "universal", "filename" : "LaunchImage.png", "scale" : "1x" },
    { "idiom" : "universal", "filename" : "LaunchImage@2x.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
""",
                encoding="utf-8",
            )

    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    for density, scale in (
        ("mdpi", 1.0),
        ("hdpi", 1.5),
        ("xhdpi", 2.0),
        ("xxhdpi", 3.0),
        ("xxxhdpi", 4.0),
    ):
        render_scale = int(scale * 2)
        directory = android_res / f"drawable-{density}"
        directory.mkdir(parents=True, exist_ok=True)
        launch_icon = contain(
            launch_source,
            (112 * render_scale, 112 * render_scale),
            (288 * render_scale, 288 * render_scale),
        )
        lockup = launch_lockup(launch_source, render_scale)
        branding = launch_branding(render_scale)
        target_scale = scale / render_scale
        for image, filename in (
            (launch_icon, "launch_image.png"),
            (lockup, "launch_lockup.png"),
            (branding, "launch_branding.png"),
        ):
            target_size = (
                round(image.width * target_scale),
                round(image.height * target_scale),
            )
            image.resize(target_size, Image.Resampling.LANCZOS).save(
                directory / filename, optimize=True
            )

    # Also put launch_image in mipmap for any legacy refs
    for density, scale in (
        ("mdpi", 1.0),
        ("hdpi", 1.5),
        ("xhdpi", 2.0),
        ("xxhdpi", 3.0),
        ("xxxhdpi", 4.0),
    ):
        px = round(48 * scale)
        mip = android_res / f"mipmap-{density}"
        mip.mkdir(parents=True, exist_ok=True)
        contain(launch_source, (int(px * 0.78), int(px * 0.78)), (px, px)).save(
            mip / "launch_image.png", optimize=True
        )

    print("wrote launch assets from", MASTER.relative_to(ROOT))
    print("  brands/launch/launch_mark.png")
    print("  android drawable-*/launch_{image,lockup,branding}.png")
    print("  ios + macos LaunchImage.imageset")


if __name__ == "__main__":
    main()
