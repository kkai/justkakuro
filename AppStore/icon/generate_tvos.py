"""tvOS Brand Assets: layered parallax app icon and Top Shelf images.

tvOS icons are nothing like the other platforms'. They are wide (5:3, not
square), they are never masked, and they are *layered*: the system slides the
layers against each other as focus moves, which is the parallax effect. A flat
image is not a valid tvOS icon, so this cannot reuse the iOS or macOS artwork.

The existing design splits along exactly the right seams for parallax: the block
field sits at the back, the clue diagonal in the middle, the numerals in front.
Moving the numerals most and the field not at all is what gives depth.

Writes a complete `TVAppIcon.brandassets` next to the other catalogues. Named
TVAppIcon rather than AppIcon because an asset catalogue cannot hold two assets
of the same name, and AppIcon.appiconset already exists for iOS and macOS.
"""
from PIL import Image, ImageDraw, ImageFont
import json, os, shutil

BLOCK = (43, 50, 64)          # Theme.block
PAPER_DARK = (20, 22, 26)     # Theme.paper, dark
CLUE_TEXT = (238, 240, 234)   # Theme.clueText
INDIGO = (124, 148, 214)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "TVAppIcon.brandassets")


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


def icon_layer(w, h, which):
    """One parallax layer. Back is opaque; the others sit on transparency."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if which == "back":
        d.rectangle([0, 0, w, h], fill=BLOCK)
    elif which == "middle":
        # The clue divider, the app's signature mark.
        d.line([(w * 0.30, h * 0.14), (w * 0.70, h * 0.86)],
               fill=CLUE_TEXT, width=max(2, int(h * 0.022)))
    else:
        f = font(int(h * 0.34))
        centred(d, (w * 0.66, h * 0.30), "17", f, CLUE_TEXT)
        centred(d, (w * 0.34, h * 0.70), "24", f, INDIGO)
    return img


def write_json(path, obj):
    with open(path, "w") as fh:
        json.dump(obj, fh, indent=2)


def imageset(path, images):
    """images: list of (filename, scale, PIL image)."""
    os.makedirs(path, exist_ok=True)
    entries = []
    for name, scale, img in images:
        img.save(os.path.join(path, name))
        entries.append({"filename": name, "idiom": "tv", "scale": scale})
    write_json(os.path.join(path, "Contents.json"),
               {"images": entries, "info": {"author": "xcode", "version": 1}})


def imagestack(path, w, h, scales):
    """A layered icon. Layers are listed front to back, which is the order the
    parallax applies them in."""
    os.makedirs(path, exist_ok=True)
    layers = []
    for which in ("Front", "Middle", "Back"):
        layer_dir = os.path.join(path, f"{which}.imagestacklayer")
        os.makedirs(layer_dir, exist_ok=True)
        write_json(os.path.join(layer_dir, "Contents.json"),
                   {"info": {"author": "xcode", "version": 1}})
        imageset(os.path.join(layer_dir, "Content.imageset"),
                 [(f"{which.lower()}@{s}.png", f"{s}x",
                   icon_layer(w * s, h * s, which.lower())) for s in scales])
        layers.append({"filename": f"{which}.imagestacklayer"})
    write_json(os.path.join(path, "Contents.json"),
               {"info": {"author": "xcode", "version": 1}, "layers": layers})


def top_shelf(w, h):
    """A wide banner: the wordmark on the dark field, with the diagonal struck
    through the K exactly as the app draws it."""
    img = Image.new("RGBA", (w, h), PAPER_DARK)
    d = ImageDraw.Draw(img)
    size = int(h * 0.30)
    f = font(size)
    just, kak = "Just ", "Kakuro"
    wj = d.textbbox((0, 0), just, font=f)[2]
    wk = d.textbbox((0, 0), kak, font=f)[2]
    x = (w - (wj + wk)) / 2
    y = h * 0.44
    l, t, r, b = d.textbbox((0, 0), just, font=f)
    d.text((x - l, y - (b - t) / 2 - t), just, font=f, fill=CLUE_TEXT)
    d.text((x + wj - l, y - (b - t) / 2 - t), kak, font=f, fill=CLUE_TEXT)
    # The diagonal, over the K.
    kx = x + wj
    d.line([(kx - size * 0.06, y + size * 0.34), (kx + size * 0.50, y - size * 0.30)],
           fill=INDIGO, width=max(2, int(size / 18)))
    sub = font(int(h * 0.09))
    centred(d, (w / 2, y + size * 0.78), "The crossword of sums", sub, (150, 154, 160))
    return img


shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(OUT, exist_ok=True)

# The App Store icon is 1x only; the home-screen icon carries 1x and 2x.
imagestack(os.path.join(OUT, "App Icon - App Store.imagestack"), 1280, 768, [1])
imagestack(os.path.join(OUT, "App Icon.imagestack"), 400, 240, [1, 2])

imageset(os.path.join(OUT, "Top Shelf Image.imageset"),
         [("top-shelf@1.png", "1x", top_shelf(1920, 720)),
          ("top-shelf@2.png", "2x", top_shelf(3840, 1440))])
imageset(os.path.join(OUT, "Top Shelf Image Wide.imageset"),
         [("top-shelf-wide@1.png", "1x", top_shelf(2320, 720)),
          ("top-shelf-wide@2.png", "2x", top_shelf(4640, 1440))])

write_json(os.path.join(OUT, "Contents.json"), {
    "assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv",
         "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv",
         "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
         "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv",
         "role": "top-shelf-image", "size": "1920x720"},
    ],
    "info": {"author": "xcode", "version": 1},
})
print("wrote", OUT)
