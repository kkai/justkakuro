"""visionOS app icon: a layered solid image stack.

visionOS icons are layered like tvOS but square, and the system masks them to a
circle, tilts the layers apart as you look around, and adds its own specular
highlight. So the artwork has to be built for a circular crop with the motif
kept well inside it, and it cannot reuse the iOS square or the tvOS 5:3 banner.

The layer split is the same one the design already suggests: the block field
behind, the clue diagonal in the middle, the numerals in front. The back layer
is opaque because it is the base the circle is cut from; the others sit on
transparency so the parallax has something to separate.

Writes `VisionAppIcon.solidimagestack`, named that way because an asset
catalogue cannot hold two assets called AppIcon and the iOS and macOS one
already claims the name.
"""
from PIL import Image, ImageDraw, ImageFont
import json, os, shutil

BLOCK = (43, 50, 64)          # Theme.block
CLUE_TEXT = (238, 240, 234)   # Theme.clueText
INDIGO = (124, 148, 214)

S = 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "VisionAppIcon.solidimagestack")


def font(size):
    for p in ["/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
              "/System/Library/Fonts/Supplemental/Georgia.ttf",
              "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default(size)


def centred(d, xy, text, f, fill):
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    d.text((xy[0] - (r - l) / 2 - l, xy[1] - (b - t) / 2 - t), text, font=f, fill=fill)


def layer(which):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if which == "back":
        # Opaque, full bleed: the system cuts the circle out of this.
        d.rectangle([0, 0, S, S], fill=BLOCK)
    elif which == "middle":
        # Kept inside the circular crop rather than running corner to corner,
        # which is what the square iOS icon does.
        d.line([(S * 0.30, S * 0.30), (S * 0.70, S * 0.70)],
               fill=CLUE_TEXT, width=int(S * 0.020))
    else:
        f = font(int(S * 0.24))
        centred(d, (S * 0.64, S * 0.36), "17", f, CLUE_TEXT)
        centred(d, (S * 0.36, S * 0.64), "24", f, INDIGO)
    return img


def write_json(path, obj):
    with open(path, "w") as fh:
        json.dump(obj, fh, indent=2)


shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(OUT, exist_ok=True)

layers = []
for which in ("Front", "Middle", "Back"):
    ldir = os.path.join(OUT, f"{which}.solidimagestacklayer")
    cdir = os.path.join(ldir, "Content.imageset")
    os.makedirs(cdir, exist_ok=True)
    write_json(os.path.join(ldir, "Contents.json"),
               {"info": {"author": "xcode", "version": 1}})
    name = f"{which.lower()}.png"
    layer(which.lower()).save(os.path.join(cdir, name))
    write_json(os.path.join(cdir, "Contents.json"), {
        "images": [{"filename": name, "idiom": "vision", "scale": "2x"}],
        "info": {"author": "xcode", "version": 1}})
    layers.append({"filename": f"{which}.solidimagestacklayer"})

write_json(os.path.join(OUT, "Contents.json"),
           {"info": {"author": "xcode", "version": 1}, "layers": layers})
print("wrote", OUT)
