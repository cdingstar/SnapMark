#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "SnapMarkIcon.iconset"
APP_ICON = RESOURCES / "SnapMarkIcon.icns"
STATUS_ICON = RESOURCES / "StatusIcon.png"


def font_path() -> str:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/SFNS.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return candidate
    return candidates[-1]


def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def gradient_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()

    top_left = (0, 196, 255)
    bottom_right = (0, 42, 220)
    warm_corner = (31, 235, 192)

    for y in range(size):
        for x in range(size):
            diagonal = (x + y) / (2 * (size - 1))
            corner = max(0.0, 1.0 - ((x / size) * 1.35 + (y / size) * 1.1))
            r = int(top_left[0] * (1 - diagonal) + bottom_right[0] * diagonal)
            g = int(top_left[1] * (1 - diagonal) + bottom_right[1] * diagonal)
            b = int(top_left[2] * (1 - diagonal) + bottom_right[2] * diagonal)
            r = int(r * (1 - corner * 0.24) + warm_corner[0] * corner * 0.24)
            g = int(g * (1 - corner * 0.24) + warm_corner[1] * corner * 0.24)
            b = int(b * (1 - corner * 0.24) + warm_corner[2] * corner * 0.24)
            pixels[x, y] = (r, g, b, 255)

    mask = rounded_rect_mask(size, int(size * 0.22))
    image.putalpha(mask)
    return image


def centered_text_position(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, size: int, y_offset: int = 0):
    bbox = draw.textbbox((0, 0), text, font=font, stroke_width=0)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    return ((size - width) / 2 - bbox[0], (size - height) / 2 - bbox[1] + y_offset)


def app_icon(size: int = 1024) -> Image.Image:
    image = gradient_background(size)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(font_path(), int(size * 0.76))
    pos = centered_text_position(draw, "S", font, size, y_offset=int(size * -0.025))

    cutout = Image.new("L", (size, size), 0)
    cutout_draw = ImageDraw.Draw(cutout)
    cutout_draw.text(pos, "S", font=font, fill=255)

    edge_size = max(3, int(size * 0.035))
    if edge_size % 2 == 0:
        edge_size += 1
    edge = ImageChops.subtract(cutout.filter(ImageFilter.MaxFilter(edge_size)), cutout)
    edge = edge.filter(ImageFilter.GaussianBlur(radius=max(1, size // 160)))

    edge_overlay = Image.new("RGBA", (size, size), (0, 9, 80, 0))
    edge_overlay.putalpha(edge.point(lambda value: int(value * 0.68)))
    image.alpha_composite(edge_overlay)

    alpha = image.getchannel("A")
    alpha = Image.composite(Image.new("L", (size, size), 0), alpha, cutout)
    image.putalpha(alpha)
    return image


def status_icon(size: int = 64) -> Image.Image:
    image = gradient_background(size)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(font_path(), int(size * 0.80))
    pos = centered_text_position(draw, "S", font, size, y_offset=int(size * -0.025))

    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border)
    inset = max(1, size // 34)
    border_draw.rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1),
        radius=int(size * 0.18),
        outline=(255, 255, 255, 150),
        width=max(2, size // 15),
    )
    image.alpha_composite(border)

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.text(
        (pos[0], pos[1] + max(1, size // 32)),
        "S",
        font=font,
        fill=(0, 15, 80, 125),
        stroke_width=max(1, size // 36),
        stroke_fill=(0, 15, 80, 125),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, size // 64)))
    image.alpha_composite(shadow)

    draw = ImageDraw.Draw(image)
    draw.text(
        pos,
        "S",
        font=font,
        fill=(255, 255, 255, 255),
        stroke_width=max(1, size // 48),
        stroke_fill=(255, 255, 255, 255),
    )
    return image


def save_iconset(master: Image.Image) -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for filename, size in sizes:
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename)


def main() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    master = app_icon()
    master.save(RESOURCES / "SnapMarkIcon-1024.png")
    status_icon().save(STATUS_ICON)
    save_iconset(master)


if __name__ == "__main__":
    main()
