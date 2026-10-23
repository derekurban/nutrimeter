"""Draw the launcher icons and the brand mark from one set of numbers.

The mark is the design system's app sub-logo (derekurban/design-system, "The logo"): its two square brackets kept
exactly, the closing one in the accent green, with the scribble replaced by this app's glyph, an apple drawn as one
monoline with its stem, on a dark rounded square. It is drawn like easyday's (its tool/icons.py): a square frame, arms
15.6% of the bracket height, and strokes at 1.3x the logo's weight so they hold up at launcher sizes; the glyph keeps
the logo's 5.5 to 6 ratio to the brackets. Everything sits inside Android's safe zone.

Rather than rasterising an SVG (no cairo here) this draws every stroke with Pillow, supersampled, as a run of discs
along the path (lines and cubic curves), which gives exact round caps and joins. tool/icon.svg is written from the
same paths.

  python -I tool/icons.py          writes prod icons under android/app/src/main/res and ios/Runner/Assets.xcassets,
                                   staging ones under android/app/src/staging/res (amber closing bracket, so the two
                                   are told apart), tool/icon.svg, and 512 px previews tool/icon-<flavor>.png

Legacy ic_launcher.png is the full rounded square. The adaptive icon (API 26+) is a solid background colour plus a
transparent foreground with the mark inside the safe zone, and a white monochrome layer for themed icons. iOS gets the
square unrounded and opaque (iOS rounds it itself).
"""
import json
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
INK, PAPER = (27, 27, 27, 255), (238, 238, 238, 255)
ACCENT = {'prod': (134, 171, 122, 255), 'staging': (224, 160, 48, 255)}
SS = 4  # supersample

# the 100-unit tile: what the launcher shows. Paths are ('M', x, y), ('L', x, y), ('C', x1, y1, x2, y2, x, y), ('Z',).
W = 7.09                 # bracket stroke
GLYPH_W = W * 5.5 / 6    # the glyph's stroke, in the logo's ratio
LEFT = [('M', 30.05, 21), ('L', 21, 21), ('L', 21, 79), ('L', 30.05, 79)]
RIGHT = [('M', 69.95, 21), ('L', 79, 21), ('L', 79, 79), ('L', 69.95, 79)]
APPLE = [
    [('M', 50, 40), ('C', 45, 35, 34, 36, 34, 49), ('C', 34, 61, 41, 69, 46, 68.5), ('C', 48, 68.2, 49, 67.6, 50, 67.6),
     ('C', 51, 67.6, 52, 68.2, 54, 68.5), ('C', 59, 69, 66, 61, 66, 49), ('C', 66, 36, 55, 35, 50, 40), ('Z',)],
    [('M', 50, 40), ('C', 50, 36, 52, 33, 57, 31)],
]
TILE_RADIUS = 22


def points(path, step):
    """The path as runs of points no more than `step` apart."""
    runs, run, cur, start = [], [], None, None

    def line_to(p):
        n = max(1, math.ceil(math.dist(cur, p) / step))
        run.extend((cur[0] + (p[0] - cur[0]) * i / n, cur[1] + (p[1] - cur[1]) * i / n) for i in range(1, n + 1))

    for s in path:
        if s[0] == 'M':
            if len(run) > 1:
                runs.append(run)
            cur = start = (s[1], s[2])
            run = [cur]
        elif s[0] == 'L':
            line_to((s[1], s[2]))
            cur = (s[1], s[2])
        elif s[0] == 'C':
            p0, p1, p2, p3 = cur, (s[1], s[2]), (s[3], s[4]), (s[5], s[6])
            n = max(2, math.ceil((math.dist(p0, p1) + math.dist(p1, p2) + math.dist(p2, p3)) / step))
            for i in range(1, n + 1):
                t = i / n
                u = 1 - t
                run.append(tuple(u ** 3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t ** 3 * d for a, b, c, d in zip(p0, p1, p2, p3)))
            cur = p3
        elif s[0] == 'Z':
            line_to(start)
            cur = start
    if len(run) > 1:
        runs.append(run)
    return runs


def stroke(d, path, width, unit, off, fill):
    """A path stroked with round caps and joins: discs closer than half a pixel apart."""
    h = width * unit / 2
    for run in points(path, 0.5 / unit):
        for x, y in run:
            cx, cy = off + x * unit, off + y * unit
            d.ellipse([cx - h, cy - h, cx + h, cy + h], fill=fill)


def mark(im, unit, off, paper, accent):
    d = ImageDraw.Draw(im)
    stroke(d, LEFT, W, unit, off, paper)
    stroke(d, RIGHT, W, unit, off, accent)
    for p in APPLE:
        stroke(d, p, GLYPH_W, unit, off, paper)


def legacy(size, accent, rounded=True):
    s = size * SS
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0) if rounded else INK)
    if rounded:
        ImageDraw.Draw(im).rounded_rectangle([0, 0, s - 1, s - 1], radius=TILE_RADIUS * s / 100, fill=INK)
    mark(im, s / 100, 0, PAPER, accent)
    return im.resize((size, size), Image.LANCZOS)


def foreground(size, accent, mono=False):
    """108-unit adaptive canvas; launchers show the middle 72, so that is where the 100-unit tile goes."""
    s = size * SS
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    mark(im, s * 72 / 108 / 100, s * 18 / 108, PAPER, PAPER if mono else accent)
    return im.resize((size, size), Image.LANCZOS)


DENSITY = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def hex_(c):
    return '#%02x%02x%02x' % c[:3]


def write_android(flavor, res):
    accent = ACCENT[flavor]
    for name, k in DENSITY.items():
        folder = os.path.join(res, f'mipmap-{name}')
        os.makedirs(folder, exist_ok=True)
        legacy(round(48 * k), accent).save(os.path.join(folder, 'ic_launcher.png'))
        foreground(round(108 * k), accent).save(os.path.join(folder, 'ic_launcher_foreground.png'))
        if flavor == 'prod':
            foreground(round(108 * k), accent, mono=True).save(os.path.join(folder, 'ic_launcher_monochrome.png'))
    if flavor == 'prod':
        any_ = os.path.join(res, 'mipmap-anydpi-v26')
        os.makedirs(any_, exist_ok=True)
        with open(os.path.join(any_, 'ic_launcher.xml'), 'w', encoding='utf-8', newline='\r\n') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    '    <background android:drawable="@color/ic_launcher_background"/>\n'
                    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n</adaptive-icon>\n')
        values = os.path.join(res, 'values')
        os.makedirs(values, exist_ok=True)
        with open(os.path.join(values, 'colors.xml'), 'w', encoding='utf-8', newline='\r\n') as f:
            f.write(f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">{hex_(INK)}</color>\n</resources>\n')
    # a 512 preview beside the script, handy for a store listing and for checking the drawing
    legacy(512, accent).save(os.path.join(ROOT, 'tool', f'icon-{flavor}.png'))


def write_ios(appiconset):
    with open(os.path.join(appiconset, 'Contents.json'), encoding='utf-8') as f:
        images = json.load(f)['images']
    for img in images:
        px = round(float(img['size'].split('x')[0]) * int(img['scale'][0]))
        legacy(px, ACCENT['prod'], rounded=False).convert('RGB').save(os.path.join(appiconset, img['filename']))


def svg_path(path):
    def n(v):
        return f'{v:g}'
    return ' '.join(s[0] + ' '.join(n(v) for v in s[1:]) if len(s) > 1 else s[0] for s in path)


def write_svg(path):
    with open(path, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Nutrimeter">'
                f'<rect width="100" height="100" rx="{TILE_RADIUS}" fill="{hex_(INK)}"/>'
                f'<g fill="none" stroke-linecap="round" stroke-linejoin="round">'
                f'<path d="{svg_path(LEFT)}" stroke="{hex_(PAPER)}" stroke-width="{W}"/>'
                f'<path d="{svg_path(RIGHT)}" stroke="{hex_(ACCENT["prod"])}" stroke-width="{W}"/>'
                + ''.join(f'<path d="{svg_path(p)}" stroke="{hex_(PAPER)}" stroke-width="{GLYPH_W:.2f}"/>' for p in APPLE)
                + '</g></svg>\n')


if __name__ == '__main__':
    write_android('prod', os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res'))
    write_android('staging', os.path.join(ROOT, 'android', 'app', 'src', 'staging', 'res'))
    write_ios(os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'))
    write_svg(os.path.join(ROOT, 'tool', 'icon.svg'))
    print('icons written')
