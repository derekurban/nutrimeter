"""Make every launcher icon from one piece of artwork, tool/icon-source.png.

The artwork is the berry cluster chosen in the November 2026 makeover: three overlapping berries and a leaf on a flat
cream square, full bleed, 1024 px. iOS takes it as it is (iOS rounds it itself). Android needs the berries apart from
the cream for its adaptive icon, so this lifts them off: the background is one flat colour, and each edge pixel is
split into how much berry it holds (alpha) and that berry's colour, taken from the nearest pixel that is all berry. The
cut-out goes back onto any background without a cream fringe. That is how staging gets the same berries on amber, so
the installs can be told apart (playground's are on aubergine).

  python -I tool/icons.py          writes prod icons under android/app/src/main/res and ios/Runner/Assets.xcassets,
                                   staging ones under android/app/src/staging/res, playground ones under android/app/src/playground/res, and 512 px previews
                                   tool/icon-<flavor>.png (needs Pillow, numpy and scipy)

Legacy ic_launcher.png is the full rounded square. The adaptive icon (API 26+) is a solid background colour plus a
transparent foreground with the berries, and a white monochrome layer for themed icons. In the monochrome layer the
berries are separate shapes: thin gaps are cut where one meets another, so the cluster still reads in one colour. To
change the icon, replace icon-source.png with another full-bleed square on a flat background and set BG to match.
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SOURCE = os.path.join(ROOT, 'tool', 'icon-source.png')
BG = (255, 247, 232)                                # the artwork's flat background
TILE = {'prod': BG, 'staging': (250, 200, 104),    # staging: the same berries on amber
        'playground': (38, 20, 44)}                 # playground: on aubergine
TILE_RADIUS = 0.22                                  # legacy icon corner, as a share of its size


def cut_out(art):
    """The artwork's berries as an RGBA image on transparency."""
    a = np.asarray(art.convert('RGB')).astype(float)
    bg = np.array(BG, float)
    diff = np.abs(a - bg).max(2)
    solid = ndimage.binary_erosion(diff > 8, iterations=4)          # surely all berry
    # the colour of the nearest solid pixel, for every pixel
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    full = a[iy, ix]
    # how far each pixel has moved from the background toward that colour
    toward = full - bg
    alpha = ((a - bg) * toward).sum(2) / np.maximum((toward * toward).sum(2), 1e-6)
    alpha = np.clip(alpha, 0, 1)
    alpha[solid] = 1
    alpha[diff <= 2] = 0
    rgba = np.dstack([full, alpha * 255]).round().clip(0, 255).astype('uint8')
    rgba[solid, :3] = a[solid].astype('uint8')
    return Image.fromarray(rgba)


def silhouette(art, berries):
    """White berries with thin gaps where one berry or the leaf meets another, for Android's themed icons."""
    a = np.asarray(art.convert('RGB')).astype(float)
    alpha = np.asarray(berries)[..., 3].astype(float) / 255
    # boundaries inside the cluster are sharp jumps in colour; the soft gradients within a shape are not
    grad = sum(np.hypot(ndimage.sobel(a[..., c], 0), ndimage.sobel(a[..., c], 1)) for c in range(3))
    inside = ndimage.binary_erosion(alpha > 0.5, iterations=6)
    seams = ndimage.binary_dilation((grad > 260) & inside, iterations=5)
    keep = Image.fromarray((alpha * 255 * ~seams).astype('uint8')).filter(ImageFilter.GaussianBlur(1.2))
    white = Image.new('RGBA', berries.size, (255, 255, 255, 0))
    white.putalpha(Image.fromarray(np.minimum(np.asarray(keep), (alpha * 255).astype('uint8'))))
    return white


def tile(berries, colour, size, rounded=True):
    """The full square at `size`: berries on `colour`, corners rounded for the legacy icon."""
    im = Image.new('RGBA', berries.size, colour + (255,))
    im.alpha_composite(berries)
    im = im.resize((size, size), Image.LANCZOS)
    if rounded:
        mask = Image.new('L', (size * 4, size * 4), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=TILE_RADIUS * size * 4, fill=255)
        im.putalpha(mask.resize((size, size), Image.LANCZOS))
    return im


def foreground(layer, size):
    """108-unit adaptive canvas; launchers show the middle 72, so that is where the artwork's square goes."""
    inner = round(size * 72 / 108)
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    im.alpha_composite(layer.resize((inner, inner), Image.LANCZOS), (off, off))
    return im


DENSITY = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def hex_(c):
    return '#%02x%02x%02x' % c[:3]


def write_android(flavor, res, berries, mono):
    colour = TILE[flavor]
    for name, k in DENSITY.items():
        folder = os.path.join(res, f'mipmap-{name}')
        os.makedirs(folder, exist_ok=True)
        tile(berries, colour, round(48 * k)).save(os.path.join(folder, 'ic_launcher.png'))
        foreground(berries, round(108 * k)).save(os.path.join(folder, 'ic_launcher_foreground.png'))
        if flavor == 'prod':
            foreground(mono, round(108 * k)).save(os.path.join(folder, 'ic_launcher_monochrome.png'))
    # each flavour has its own background colour; staging's overrides prod's
    values = os.path.join(res, 'values')
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, 'colors.xml'), 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">{hex_(colour)}</color>\n</resources>\n')
    if flavor == 'prod':
        any_ = os.path.join(res, 'mipmap-anydpi-v26')
        os.makedirs(any_, exist_ok=True)
        with open(os.path.join(any_, 'ic_launcher.xml'), 'w', encoding='utf-8', newline='\r\n') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    '    <background android:drawable="@color/ic_launcher_background"/>\n'
                    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n</adaptive-icon>\n')
    # a 512 preview beside the script, handy for a store listing and for checking the result
    tile(berries, colour, 512).save(os.path.join(ROOT, 'tool', f'icon-{flavor}.png'))


def write_ios(appiconset, art):
    with open(os.path.join(appiconset, 'Contents.json'), encoding='utf-8') as f:
        images = json.load(f)['images']
    for img in images:
        px = round(float(img['size'].split('x')[0]) * int(img['scale'][0]))
        art.convert('RGB').resize((px, px), Image.LANCZOS).save(os.path.join(appiconset, img['filename']))


if __name__ == '__main__':
    art = Image.open(SOURCE).convert('RGB')
    berries = cut_out(art)
    mono = silhouette(art, berries)
    write_android('prod', os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res'), berries, mono)
    write_android('staging', os.path.join(ROOT, 'android', 'app', 'src', 'staging', 'res'), berries, mono)
    write_android('playground', os.path.join(ROOT, 'android', 'app', 'src', 'playground', 'res'), berries, mono)
    write_ios(os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'), art)
    print('icons written')
