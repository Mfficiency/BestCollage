"""Generates every app icon from assets/icon_source.png.

    python3 tool/make_icons.py [preview.png]

The icon is the source image exactly as it is — no tile, no rounded corners,
no recolouring — only resized to each size.

Writes:
  * Android legacy icons      res/mipmap-*/ic_launcher.png (48 dp, the image)
  * Android adaptive icon     res/mipmap-*/ic_launcher_foreground.png (108 dp,
    the whole image) on a white background — see
    res/mipmap-anydpi-v26/ic_launcher.xml. The image's mark takes ~52% of it,
    so it lands inside the 66 dp safe zone; only the white margin is masked.
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

# Themed (monochrome) icon: mark size in dp, inside the 66 dp safe zone.
MONO_MARK_DP = 46

INK = (17, 17, 17)


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


def main():
    src = Image.open(SOURCE).convert('RGB')

    def sized(px):
        return src.resize((px, px), Image.LANCZOS)

    # Monochrome only: the ink becomes alpha (dark = opaque, paper = clear).
    gray = ImageOps.grayscale(src)
    alpha = gray.point(lambda v: 0 if v > 248 else 255 - v)
    ink = Image.new('RGBA', src.size, INK + (255,))
    ink.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 6 else 0).getbbox()
    side = max(bbox[2] - bbox[0], bbox[3] - bbox[1])

    for d, s in DENSITIES.items():
        px = round(108 * s)
        sized(px).save(f'{RES}/mipmap-{d}/ic_launcher_foreground.png',
                       optimize=True)
        mono = crop_padded(ink, square_around(bbox, side * 108 / MONO_MARK_DP))
        mono.resize((px, px), Image.LANCZOS).save(
            f'{RES}/mipmap-{d}/ic_launcher_monochrome.png', optimize=True)
        sized(round(48 * s)).save(f'{RES}/mipmap-{d}/ic_launcher.png',
                                  optimize=True)

    sized(512).save('assets/app_icon.png', optimize=True)
    sized(256).save(
        'windows/runner/resources/app_icon.ico',
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128),
               (256, 256)])

    if len(sys.argv) > 1:
        # What a launcher shows: the visible 72 dp of the adaptive icon cut
        # to a circle (the strictest shape), then the legacy icon.
        visible = sized(324).crop((54, 54, 270, 270))
        m = Image.new('L', (216, 216), 0)
        ImageDraw.Draw(m).ellipse((0, 0, 215, 215), fill=255)
        sheet = Image.new('RGB', (740, 260))
        for i, wall in enumerate(((176, 196, 222), (60, 70, 90))):
            sheet.paste(wall, (i * 370, 0, i * 370 + 370, 260))
            sheet.paste(visible, (i * 370 + 10, 22), m)
            sheet.paste(sized(120), (i * 370 + 240, 70))
        sheet.save(sys.argv[1])


if __name__ == '__main__':
    main()
