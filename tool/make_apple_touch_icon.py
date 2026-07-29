#!/usr/bin/env python3
"""Builds web/apple-touch-icon-180.png from assets/icon/app_icon.png.

iOS home-screen icons are not the manifest icons. Safari uses the
`<link rel="apple-touch-icon">` target, and it wants something the other
platforms do not:

* **Opaque.** iOS composites transparent pixels as solid black. The source
  artwork carries its own transparent rounded corners, so on iOS those corners
  render black before iOS applies its own squircle mask.
* **Full-bleed square.** iOS rounds the icon itself. Supplying pre-rounded
  artwork means the rounding happens twice.
* **180x180.** Apple's size for modern iPhones; anything else is rescaled.

The transparent corners are flattened onto the plate colour sampled from the
artwork itself, so the square extends the existing background rather than
introducing a new one, and iOS's mask cuts it back to the same shape.

Re-run after changing the source icon:

    python3 tool/make_apple_touch_icon.py
"""

from PIL import Image

SRC = "assets/icon/app_icon.png"
OUT = "web/apple-touch-icon-180.png"
SIZE = 180


def plate_colour(im: Image.Image) -> tuple[int, int, int]:
    """The artwork's own background, sampled just inside the rounded plate."""
    w, h = im.size
    samples = [
        im.getpixel((w // 2, int(h * 0.06))),
        im.getpixel((int(w * 0.06), h // 2)),
        im.getpixel((w // 2, int(h * 0.94))),
        im.getpixel((int(w * 0.94), h // 2)),
    ]
    opaque = [s for s in samples if s[3] > 250]
    if not opaque:
        return (0, 0, 0)
    return tuple(sum(c[i] for c in opaque) // len(opaque) for i in range(3))


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    bg = plate_colour(src)
    flat = Image.new("RGB", src.size, bg)
    flat.paste(src, mask=src.split()[3])
    flat.resize((SIZE, SIZE), Image.LANCZOS).save(OUT, "PNG", optimize=True)
    print(f"{OUT}: {SIZE}x{SIZE} opaque, plate #{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}")


if __name__ == "__main__":
    main()
