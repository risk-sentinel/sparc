#!/usr/bin/env python3
"""Regenerate the favicon set and link-preview image from the SPARC logo (#936).

A ONE-OFF tool, not a runtime or build dependency. The outputs are committed to
`public/`; this exists so a logo change is reproducible instead of a manual
crop somebody has to reverse-engineer later.

    python3 script/generate_icons.py

Requires Pillow. Deliberately Python rather than a rake task: this repo has no
usable Ruby image tooling — no ImageMagick binary, no vips, and the
`image_processing` gem is vestigial. Adding one for a job that runs once per
logo change would be a runtime dependency bought for nothing.

── Why the icons are cut from the medallion, not the whole logo ─────────────

`sparc_logo.png` is a LOCKUP: a circular medallion above a "SPARC" wordmark,
separated by a fully transparent band (measured from the alpha channel at
y759–793). Rendered at 16px the whole lockup turns the wordmark into an
illegible grey smear and shrinks the medallion to a dot. The medallion alone is
already circular and high contrast, so it survives the size — at 32px the
lightning bolt is unmistakable.

So: medallion for every icon, full lockup for the 1200×630 preview, where there
is room for the wordmark to be read.

── Why pad to square instead of resizing ───────────────────────────────────

The source is portrait (832×988). Resizing a non-square image into a square
icon squashes the mark, which is most of what makes a favicon look wrong.
Padding preserves the aspect ratio and centres it.
"""

from __future__ import annotations

import base64
import io
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "app/assets/images/sparc_logo.png"
PUBLIC = ROOT / "public"

# Measured from the source alpha channel, not eyeballed: the medallion occupies
# y31–759 and the wordmark y793–946, with a transparent band between them.
MEDALLION_BOX = (0, 31, 832, 759)

# iOS composites this onto a tile and renders transparency as black, so it gets
# an opaque ground. Sampled from the medallion's outer ring rather than guessed.
APPLE_TOUCH_BG = (26, 32, 54)

# The preview card's ground. Dark so the medallion's glow reads, and close to
# the app's own dark theme so a shared link looks like the product.
OG_BG = (24, 26, 32)
OG_SIZE = (1200, 630)

# Embedded in icon.svg as a data URI. 256 rather than 512: a browser choosing
# the SVG wants scalability, and .ico/.png already cover the small sizes, so
# doubling the bytes buys very little.
SVG_RASTER = 256


def square_pad(img: Image.Image) -> Image.Image:
    """Centre `img` on a transparent square canvas, preserving aspect ratio."""
    img = img.crop(img.getbbox())
    side = max(img.size)
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return out


def flatten(img: Image.Image, background: tuple[int, int, int]) -> Image.Image:
    out = Image.new("RGB", img.size, background)
    out.paste(img, mask=img.getchannel("A"))
    return out


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    medallion = square_pad(source.crop(MEDALLION_BOX))
    lockup = square_pad(source)

    # favicon.ico — multi-resolution so the browser picks per context rather
    # than downscaling one size badly.
    medallion.save(PUBLIC / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])

    medallion.resize((512, 512), Image.LANCZOS).save(PUBLIC / "icon.png", optimize=True)

    flatten(medallion.resize((180, 180), Image.LANCZOS), APPLE_TOUCH_BG).save(
        PUBLIC / "apple-touch-icon.png", optimize=True
    )

    # icon.svg wraps the raster. There is no vector source in the repo, and a
    # hand-drawn approximation would be a NEW mark rather than the logo.
    buf = io.BytesIO()
    medallion.resize((SVG_RASTER, SVG_RASTER), Image.LANCZOS).save(buf, format="PNG", optimize=True)
    encoded = base64.b64encode(buf.getvalue()).decode("ascii")
    (PUBLIC / "icon.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">\n'
        f'  <image href="data:image/png;base64,{encoded}" width="512" height="512"/>\n'
        "</svg>\n"
    )

    # og-preview.png — the FULL lockup, which is legible at this size.
    card = Image.new("RGBA", OG_SIZE, OG_BG + (255,))
    mark = lockup.copy()
    mark.thumbnail((int(OG_SIZE[1] * 0.78), int(OG_SIZE[1] * 0.78)), Image.LANCZOS)
    card.alpha_composite(
        mark, ((OG_SIZE[0] - mark.width) // 2, (OG_SIZE[1] - mark.height) // 2)
    )
    card.convert("RGB").save(PUBLIC / "og-preview.png", optimize=True)

    for name in ("favicon.ico", "icon.svg", "icon.png", "apple-touch-icon.png", "og-preview.png"):
        path = PUBLIC / name
        print(f"  {name:24} {path.stat().st_size:>9,} bytes")


if __name__ == "__main__":
    main()
