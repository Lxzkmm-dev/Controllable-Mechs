import math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter

# Paths are relative to this folder so the scripts run from the repo on Windows or Linux.
HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "shots")  # in-game screenshots / cleaned bases (not committed)
OUT = os.path.join(HERE, "out")      # rendered mockups

# First font found wins (Linux, then Windows).
SANS = ["/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "C:/Windows/Fonts/arialbd.ttf"]
MONO = ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
        "C:/Windows/Fonts/consolab.ttf", "C:/Windows/Fonts/courbd.ttf"]
_f = {}


def font(size, mono=False):
    k = (size, mono)
    if k not in _f:
        path = next((p for p in (MONO if mono else SANS) if os.path.exists(p)), None)
        _f[k] = ImageFont.truetype(path, size) if path else ImageFont.load_default(size)
    return _f[k]


def here(name):
    return os.path.join(HERE, name)


def shot(name, size=None):
    # Background screenshot from shots/. Missing -> a flat dark placeholder, so layout still renders.
    p = os.path.join(SHOTS, name)
    if os.path.exists(p):
        im = Image.open(p).convert("RGB")
        return im.resize(size, Image.LANCZOS) if size else im
    print("WARNING: %s not found, drawing on a placeholder background" % p, file=sys.stderr)
    return Image.new("RGB", size or (2000, 840), (38, 42, 46))


def out(name):
    os.makedirs(OUT, exist_ok=True)
    return os.path.join(OUT, name)


class Kit:
    def __init__(self, im, accent):
        self.im = im
        self.d = ImageDraw.Draw(im, "RGBA")
        self.A = accent

    def t(self, x, y, s, size=15, col=None, anchor="la", mono=False, stroke=2):
        col = col or (240, 244, 240)
        self.d.text((x, y), s, font=font(size, mono), fill=col, anchor=anchor,
                    stroke_width=stroke, stroke_fill=(0, 0, 0))

    def line(self, pts, col=None, w=2):
        col = col or self.A
        self.d.line(pts, fill=(0, 0, 0, 190), width=w + 2)
        self.d.line(pts, fill=col, width=w)

    def corners(self, x0, y0, x1, y1, L=12, col=None, w=2):
        for (x, y, sx, sy) in [(x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)]:
            self.line([(x, y + sy * L), (x, y), (x + sx * L, y)], col, w)

    def arc(self, cx, cy, r, a0, a1, col=None, w=2):
        col = col or self.A
        box = (cx - r, cy - r, cx + r, cy + r)
        self.d.arc(box, a0, a1, fill=(0, 0, 0, 190), width=w + 2)
        self.d.arc(box, a0, a1, fill=col, width=w)

    def bar(self, x, y, w, h, frac, col=None, segs=10):
        col = col or self.A
        self.d.rectangle((x - 1, y - 1, x + w + 1, y + h + 1), outline=(0, 0, 0, 200), width=2)
        self.d.rectangle((x, y, x + w, y + h), outline=(230, 235, 230), width=1)
        sw = (w - 2) / segs
        for i in range(segs):
            if (i + 0.5) / segs <= frac:
                self.d.rectangle((x + 2 + i * sw, y + 2, x + (i + 1) * sw - 1, y + h - 2), fill=col + (230,))

    def note(self, x, y, s):
        w = font(13, True).getlength(s)
        self.d.rounded_rectangle((x - 4, y - 3, x + w + 4, y + 17), 4, fill=(255, 0, 140, 215))
        self.d.text((x, y), s, font=font(13, True), fill=(255, 255, 255))

    def paste_sprite(self, path, x, y, tint, scale=1.0):
        sp = Image.open(here(path)).convert("RGB")
        if scale != 1.0:
            sp = sp.resize((int(sp.width * scale), int(sp.height * scale)), Image.LANCZOS)
        hsv = sp.convert("HSV")
        h, s, v = hsv.split()
        mask = ImageChops.multiply(s.point(lambda p: 255 if p > 110 else 0), v.point(lambda p: 255 if p > 120 else 0))
        mask = mask.filter(ImageFilter.MaxFilter(3))
        lum = sp.convert("L").point(lambda p: min(255, p * 1.3))
        col = Image.merge("RGB", [lum.point(lambda p, c=c: p * c // 255) for c in tint])
        self.im.paste(col, (x, y), mask)
        self.d = ImageDraw.Draw(self.im, "RGBA")


def scanlines(im, alpha=18, step=3):
    d = ImageDraw.Draw(im, "RGBA")
    for y in range(0, im.height, step):
        d.line([(0, y), (im.width, y)], fill=(0, 0, 0, alpha))
