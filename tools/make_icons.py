#!/usr/bin/env python3
"""Generate MathGate's Android launcher icon, iOS app icon, website logo and favicon.

The mark is a white padlock on the app's purple, with a pi knocked out of the lock body so the
background shows through. Run from anywhere:  python3 tools/make_icons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
WEBSITE = REPO.parent / "mathgate-website"

PURPLE = (124, 77, 255, 255)      # #7C4DFF, the app accent
PURPLE_DARK = (92, 53, 204, 255)  # #5C35CC
WHITE = (255, 255, 255, 255)
FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf",
]

S = 1024  # master size; everything is downsampled from here


def font(size):
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def gradient(size):
    """Vertical purple gradient."""
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(size - 1, 1)
        d.line(
            [(0, y), (size, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(PURPLE, PURPLE_DARK)),
        )
    return img


def foreground(size):
    """White padlock with a transparent pi, on a transparent canvas.

    Drawn inside the middle ~60% so it survives Android's adaptive-icon mask.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = size / 100.0  # 1 unit = 1% of the canvas

    body_w, body_h = 46 * u, 38 * u
    body_x0 = (size - body_w) / 2
    body_y0 = size / 2 - 6 * u
    d.rounded_rectangle(
        [body_x0, body_y0, body_x0 + body_w, body_y0 + body_h],
        radius=6 * u,
        fill=WHITE,
    )

    # Shackle: an arc thick enough to read at 48px.
    shackle_w = 28 * u
    shackle_x0 = (size - shackle_w) / 2
    shackle_top = body_y0 - 22 * u
    d.arc(
        [shackle_x0, shackle_top, shackle_x0 + shackle_w, shackle_top + 34 * u],
        start=180,
        end=360,
        fill=WHITE,
        width=int(7 * u),
    )

    # Knock the pi out of the lock body.
    glyph = Image.new("L", (size, size), 0)
    gd = ImageDraw.Draw(glyph)
    f = font(int(30 * u))
    box = gd.textbbox((0, 0), "π", font=f)
    gd.text(
        (
            (size - (box[2] - box[0])) / 2 - box[0],
            body_y0 + (body_h - (box[3] - box[1])) / 2 - box[1],
        ),
        "π",
        font=f,
        fill=255,
    )
    img.putalpha(Image.composite(Image.new("L", (size, size), 0), img.getchannel("A"), glyph))
    return img


def composed(size, circle=False):
    """Foreground over the gradient, rounded square or circle."""
    base = gradient(size)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    if circle:
        md.ellipse([0, 0, size - 1, size - 1], fill=255)
    else:
        md.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    out = Image.alpha_composite(base, foreground(size))
    out.putalpha(mask)
    return out


def save(img, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)
    print(f"  {path.relative_to(path.parents[len(path.parts) - 3])}  {size}x{size}")


def main():
    res = REPO / "android/app/src/main/res"
    master_square = composed(S)
    master_circle = composed(S, circle=True)
    master_fg = foreground(S)

    # Legacy launcher icons (API < 26 fallback) and round variants.
    for bucket, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(master_square, res / f"mipmap-{bucket}/ic_launcher.png", px)
        save(master_circle, res / f"mipmap-{bucket}/ic_launcher_round.png", px)

    # Adaptive-icon foreground: 108dp canvas, transparent outside the mark.
    for bucket, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]:
        save(master_fg, res / f"drawable-{bucket}/ic_launcher_foreground_asset.png", px)

    # iOS: one 1024 master, which Xcode downsamples for every slot. The shield extension shows
    # the mark on its own dark background, so it gets the transparent foreground instead.
    ios = REPO / "ios/Assets.xcassets"
    save(master_square, ios / "AppIcon.appiconset/mathgate_1024.png", 1024)
    save(master_fg, ios / "ShieldIcon.imageset/shield_icon.png", 512)
    write_ios_catalog(ios)

    # Website and README assets.
    if WEBSITE.exists():
        save(master_square, WEBSITE / "logo.png", 512)
        save(master_square, WEBSITE / "favicon.png", 64)
    save(master_square, REPO / "screenshots/mathgate_logo.png", 512)


def write_ios_catalog(ios):
    """Asset-catalog metadata. Single-size app icons have been enough since Xcode 14."""
    (ios / "Contents.json").write_text(
        '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n'
    )
    (ios / "AppIcon.appiconset/Contents.json").write_text(
        """{
  "images" : [
    {
      "filename" : "mathgate_1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
    )
    (ios / "ShieldIcon.imageset/Contents.json").write_text(
        """{
  "images" : [
    { "filename" : "shield_icon.png", "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "original" }
}
"""
    )


if __name__ == "__main__":
    main()
