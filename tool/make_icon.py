import math
from PIL import Image, ImageDraw

S, SS = 1024, 4
N = S * SS
BG = (11, 15, 20, 255)
GREEN = (49, 196, 141, 255)
CX = 512


def cubic(p0, p1, p2, p3, n=120):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((
            u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0],
            u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1],
        ))
    return out


def taper(centre, w0, w1, power=1.6):
    """Thickens a centre-line into a closed shape that tapers to a point.

    Offsetting a centre-line keeps the horn's thickness under direct control;
    drawing two independent edges by eye produced thin slivers that read as
    ears rather than horns.
    """
    left, right = [], []
    n = len(centre)
    for i, (x, y) in enumerate(centre):
        t = i / (n - 1)
        w = (w0 + (w1 - w0) * (t ** power)) / 2
        j = min(i + 1, n - 1)
        k = max(i - 1, 0)
        dx, dy = centre[j][0] - centre[k][0], centre[j][1] - centre[k][1]
        m = math.hypot(dx, dy) or 1
        nx, ny = -dy / m, dx / m
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


def horn():
    # Out first, then up: a short thick crescent, not a long thin spike.
    centre = cubic((CX + 126, 470), (CX + 292, 442), (CX + 386, 386), (CX + 398, 268))
    return taper(centre, 112, 6)


def mirror(pts):
    return [(CX - (x - CX), y) for (x, y) in pts]


def head():
    left = cubic((CX - 188, 452), (CX - 202, 606), (CX - 160, 700), (CX - 108, 744))
    muzzle = cubic((CX - 108, 744), (CX - 74, 806), (CX + 74, 806), (CX + 108, 744))
    right = cubic((CX + 108, 744), (CX + 160, 700), (CX + 202, 606), (CX + 188, 452))
    brow = cubic((CX + 188, 452), (CX + 104, 410), (CX - 104, 410), (CX - 188, 452))
    return left + muzzle + right + brow


def blaze():
    return [
        (CX, 462),
        (CX + 82, 554), (CX + 40, 554), (CX + 40, 646),
        (CX - 40, 646), (CX - 40, 554), (CX - 82, 554),
    ]


def draw_bull(img, scale=1.0, dy=0):
    layer = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def place(pts):
        return [((CX + (x - CX) * scale) * SS,
                 ((y - 512) * scale + 512 + dy) * SS) for (x, y) in pts]

    for shape in (head(), horn(), mirror(horn())):
        d.polygon(place(shape), fill=GREEN)
    d.polygon(place(blaze()), fill=(0, 0, 0, 0))
    img.alpha_composite(layer)


full = Image.new('RGBA', (N, N), BG)
draw_bull(full, scale=0.86, dy=8)
full.resize((S, S), Image.LANCZOS).save('assets/icon/icon.png')

fg = Image.new('RGBA', (N, N), (0, 0, 0, 0))
draw_bull(fg, scale=0.64, dy=6)
fg.resize((S, S), Image.LANCZOS).save('assets/icon/icon_foreground.png')
print('ok')
