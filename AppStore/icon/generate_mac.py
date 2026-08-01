"""macOS app icon set: the clue cell, as a Big Sur rounded tile.

The iOS icon is full-bleed artwork that the system masks. macOS does not mask:
the rounded rectangle has to be drawn, sitting in a transparent field with the
standard margin, or the icon looks wrong beside every other app in the Dock.
So this is a re-render of the same design, not a resize of the iOS PNG.

Geometry follows Apple's grid: on a 1024 canvas the tile is 824x824 centred,
with a corner radius of 22.37% of the tile. Alpha is kept, unlike the iOS icon
which had to be flattened for ITMS-90717 — that rule is App Store artwork, not
macOS icons, and a flattened macOS icon would show black corners.
"""
from PIL import Image, ImageDraw, ImageFont
import os

BLOCK = (43, 50, 64)          # Theme.block, the clue cell
CLUE_TEXT = (238, 240, 234)   # Theme.clueText
INDIGO = (124, 148, 214)      # the down-clue numeral, as on the iOS icon

# Apple's Big Sur icon grid.
TILE_RATIO = 824 / 1024
RADIUS_RATIO = 0.2237

OUT = os.path.dirname(os.path.abspath(__file__))
SIZES = [16, 32, 64, 128, 256, 512, 1024]


def font(size):
    for p in ["/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
              "/System/Library/Fonts/Supplemental/Georgia.ttf",
              "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default(size)


def render(px):
    """Draw at 4x and downsample, so the diagonal and numerals stay clean."""
    scale = 4
    S = px * scale
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    tile = S * TILE_RATIO
    off = (S - tile) / 2
    box = (off, off, off + tile, off + tile)
    d.rounded_rectangle(box, radius=tile * RADIUS_RATIO, fill=BLOCK)

    # The clue divider: corner to corner of the tile, inset so it does not
    # collide with the rounded corners.
    inset = tile * 0.13
    d.line([(off + inset, off + inset), (off + tile - inset, off + tile - inset)],
           fill=CLUE_TEXT, width=max(1, int(tile * 0.018)))

    # 17 above the divider, 24 below, exactly as the iOS icon reads.
    f = font(int(tile * 0.30))
    for text, colour, (fx, fy) in [("17", CLUE_TEXT, (0.70, 0.29)),
                                   ("24", INDIGO, (0.30, 0.71))]:
        l, t, r, b = d.textbbox((0, 0), text, font=f)
        d.text((off + tile * fx - (r - l) / 2 - l,
                off + tile * fy - (b - t) / 2 - t), text, font=f, fill=colour)

    return img.resize((px, px), Image.LANCZOS)


for px in SIZES:
    render(px).save(os.path.join(OUT, f"mac-{px}.png"))
    print(f"  mac-{px}.png")
