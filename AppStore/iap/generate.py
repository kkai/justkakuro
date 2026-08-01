"""1024x1024 in-app purchase image: lesson two's board, solved.

Same grid the app ships and the website plays, so it is a real board rather than
a mock-up. Palette and the clue divider direction follow the app.
"""
from PIL import Image, ImageDraw, ImageFont
import os

S = 1024
PAPER = (242, 243, 238)
BLOCK = (43, 50, 64)
CLUE_TEXT = (238, 240, 234)
DONE = (72, 133, 106)
GRID = (188, 191, 186)
INDIGO = (59, 91, 165)

# row, col -> ("clue", across, down) | ("white", digit) | ("block",)
SOL = {(1, 1): 1, (1, 2): 2, (1, 3): 3, (2, 1): 3, (2, 2): 9, (2, 3): 7}
CLUES = {(0, 1): (None, 4), (0, 2): (None, 11), (0, 3): (None, 10),
         (1, 0): (6, None), (2, 0): (19, None)}
ROWS, COLS = 3, 4


def font(size, serif=True):
    candidates = ["/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
                  "/System/Library/Fonts/Supplemental/Georgia.ttf",
                  "/Library/Fonts/Georgia.ttf",
                  "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf"]
    for p in candidates:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default(size)


img = Image.new("RGB", (S, S), PAPER)
d = ImageDraw.Draw(img)

# Board geometry: centred, generous margin so it reads at small sizes.
cell = 196
bw, bh = COLS * cell, ROWS * cell
x0, y0 = (S - bw) // 2, (S - bh) // 2 - 24

for r in range(ROWS):
    for c in range(COLS):
        x, y = x0 + c * cell, y0 + r * cell
        box = [x, y, x + cell, y + cell]
        if (r, c) in CLUES or ((r, c) not in SOL):
            d.rectangle(box, fill=BLOCK)
            if (r, c) in CLUES:
                across, down = CLUES[(r, c)]
                # Divider runs top-left to bottom-right, as in the app.
                d.line([x, y, x + cell, y + cell], fill=(120, 128, 142), width=3)
                f = font(64)
                if across is not None:
                    t = str(across)
                    w = d.textlength(t, font=f)
                    d.text((x + cell - w - 22, y + 16), t, font=f, fill=CLUE_TEXT)
                if down is not None:
                    t = str(down)
                    d.text((x + 22, y + cell - 84), t, font=f, fill=CLUE_TEXT)
        else:
            d.rectangle(box, fill=(255, 255, 255))
            t = str(SOL[(r, c)])
            f = font(104)
            w = d.textlength(t, font=f)
            bbox = f.getbbox(t)
            d.text((x + (cell - w) / 2, y + (cell - (bbox[3] - bbox[1])) / 2 - bbox[1]),
                   t, font=f, fill=DONE)

# Grid lines over the whole board, then a solid outer edge.
for c in range(1, COLS):
    d.line([x0 + c * cell, y0, x0 + c * cell, y0 + bh], fill=GRID, width=3)
for r in range(1, ROWS):
    d.line([x0, y0 + r * cell, x0 + bw, y0 + r * cell], fill=GRID, width=3)
d.rectangle([x0, y0, x0 + bw, y0 + bh], outline=BLOCK, width=6)

# One line of type, in the app's voice.
f = font(58)
label = "Every lesson, drill and hint"
w = d.textlength(label, font=f)
d.text(((S - w) / 2, y0 + bh + 58), label, font=f, fill=(34, 38, 43))

out = "/private/tmp/claude-501/-Users-kai-work-areas-ios/2a972416-4e70-4458-be07-19cff6116593/scratchpad/iap_image.png"
flat = Image.new("RGB", img.size)
flat.putdata(list(img.convert("RGB").getdata()))
flat.save(out, format="PNG", optimize=True)
chk = Image.open(out)
print(f"wrote {out}")
print(f"  mode={chk.mode} size={chk.size} bytes={os.path.getsize(out)}")
