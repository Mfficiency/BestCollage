"""Generates every app icon from assets/icon_source.png (black mark on white).

    python3 tool/make_icons.py [preview.png]

The icon is the logo as designed: the black mark on a white rounded square.
Android launchers cut adaptive icons to their own shape (often a circle), so
the white tile is drawn *inside* a transparent icon, small enough to fit any
launcher shape — the launcher shows the tile with its corners, never a circle.

Writes:
  * Android legacy icons      res/mipmap-*/ic_launcher.png (48 dp)
  * Android adaptive icon     res/mipmap-*/ic_launcher_foreground.png (108 dp,
    white tile + mark on transparent) — see
    res/mipmap-anydpi-v26/ic_launcher.xml (transparent background)
  * Android 13 themed icon    res/mipmap-*/ic_launcher_monochrome.png (just
    the mark; the launcher tints it)
  * Windows                   windows/runner/resources/app_icon.ico
  * assets/app_icon.png       512 px
Needs Pillow.
"""
import sys

from PIL import Image, ImageDraw, ImageOps

SOURCE = 'assets/icon_source.png'
RES = 'android/app/src/main/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# Adaptive icons are 108 dp; launchers show the middle 72 dp cut to their
# shape. A 56 dp tile with 13 dp corners stays inside a 72 dp circle
# ((28 - 13) * sqrt(2) + 13 = 34.2 < 36), so no launcher clips it.
TILE_DP = 56
TILE_RADIUS_DP = 13
# The mark's share of the tile (the rest is white margin).
MARK_IN_TILE = 0.66
# Themed (monochrome) icon: mark size in dp, inside the 66 dp safe zone.
MONO_MARK_DP = 46

INK = (17, 17, 17)
WHITE = (255, 255, 255)


def square_around(bbox, side):
    cx, cy = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
    return tuple(round(v) for v in
                 (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))


def crop_padded(img, box):
    """Crops [box], which may reach past the edges (filled transparent)."""
    w, h = img.size
    canvas = Image.new('RGBA', (w * 3, h * 3), (0, 0, 0, 0))
    canvas.paste(img, (w, h))
    return canvas.crop((box[0] + w, box[1] + h, box[2] + w, box[3] + h))


def tile_icon(mark, size, tile, radius):
    """A [size] px transparent square with a white rounded [tile] px square in
    the middle and the mark centred on it."""
    scale = 4  # draw big, then downsample, for smooth corners
    big = size * scale
    out = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    t = tile * scale
    o = (big - t) / 2
    ImageDraw.Draw(out).rounded_rectangle(
        (o, o, o + t, o + t), radius * scale, fill=WHITE + (255,))
    m = round(t * MARK_IN_TILE)
    mk = mark.resize((m, m), Image.LANCZOS)
    out.alpha_composite(mk, (round((big - m) / 2), round((big - m) / 2)))
    return out.resize((size, size), Image.LANCZOS)


def main():
    src = Image.open(SOURCE).convert('RGB')
    gray = ImageOps.grayscale(src)
    # The ink becomes alpha: dark = opaque, the white paper = transparent, and
    # the motion-blur fade keeps its softness.
    alpha = gray.point(lambda v: 0 if v > 248 else 255 - v)
    ink = Image.new('RGBA', src.size, INK + (255,))
    ink.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 6 else 0).getbbox()
    side = max(bbox[2] - bbox[0], bbox[3] - bbox[1])
    mark = crop_padded(ink, square_around(bbox, side))  # tight, square

    for d, s in DENSITIES.items():
        px = round(108 * s)
        tile_icon(mark, px, TILE_DP * s, TILE_RADIUS_DP * s).save(
            f'{RES}/mipmap-{d}/ic_launcher_foreground.png', optimize=True)
        mono = crop_padded(ink, square_around(bbox, side * 108 / MONO_MARK_DP))
        mono.resize((px, px), Image.LANCZOS).save(
            f'{RES}/mipmap-{d}/ic_launcher_monochrome.png', optimize=True)
        lp = round(48 * s)
        # Legacy: the tile nearly fills the icon (old launchers don't mask).
        tile_icon(mark, lp, lp * 0.92, lp * 0.2).save(
            f'{RES}/mipmap-{d}/ic_launcher.png', optimize=True)

    tile_icon(mark, 512, 512 * 0.92, 512 * 0.2).save(
        'assets/app_icon.png', optimize=True)
    tile_icon(mark, 256, 256 * 0.92, 256 * 0.2).save(
        'windows/runner/resources/app_icon.ico',
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128),
               (256, 256)])

    if len(sys.argv) > 1:
        # What a launcher shows on a light and a dark wallpaper: the visible
        # 72 dp of the adaptive icon, cut to a circle (the strictest shape),
        # then the legacy icon.
        fg = tile_icon(mark, 324, TILE_DP * 3, TILE_RADIUS_DP * 3)
        visible = fg.crop((54, 54, 270, 270))
        m = Image.new('L', (216, 216), 0)
        ImageDraw.Draw(m).ellipse((0, 0, 215, 215), fill=255)
        clipped = Image.new('RGBA', (216, 216), (0, 0, 0, 0))
        clipped.paste(visible, (0, 0), m)
        sheet = Image.new('RGBA', (740, 260), (0, 0, 0, 255))
        for i, wall in enumerate(((176, 196, 222), (60, 70, 90))):
            sheet.paste(wall + (255,), (i * 370, 0, i * 370 + 370, 260))
            sheet.alpha_composite(clipped, (i * 370 + 10, 22))
            sheet.alpha_composite(tile_icon(mark, 120, 110, 24),
                                  (i * 370 + 240, 70))
        sheet.convert('RGB').save(sys.argv[1])


if __name__ == '__main__':
    main()
