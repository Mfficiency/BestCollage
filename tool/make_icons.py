"""Generates every app icon from assets/icon_source.png (black mark on white).

    python3 tool/make_icons.py [preview.png]

Writes:
  * Android legacy icons      res/mipmap-*/ic_launcher.png (48 dp, white square)
  * Android adaptive icon     res/mipmap-*/ic_launcher_foreground.png (108 dp,
    transparent; also used as the Android 13 themed "monochrome" layer) on a
    white background — see res/mipmap-anydpi-v26/ic_launcher.xml
  * Windows                   windows/runner/resources/app_icon.ico
  * assets/app_icon.png       512 px
Needs Pillow.
"""
import sys

from PIL import Image, ImageDraw, ImageOps

SOURCE = 'assets/icon_source.png'
RES = 'android/app/src/main/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# Adaptive icons are 108 dp; launchers may mask all but a 66 dp circle. The
# mark is square-ish, so it must fit inside that circle: ~46 dp side.
ADAPTIVE_CONTENT_DP = 46
# Legacy / desktop icons: mark size as a share of the square.
LEGACY_FILL = 0.80


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
    gray = ImageOps.grayscale(src)
    # The ink becomes alpha: dark = opaque, the white paper = transparent, and
    # the motion-blur fade keeps its softness.
    alpha = gray.point(lambda v: 0 if v > 248 else 255 - v)
    ink = Image.new('RGBA', src.size, (17, 17, 17, 255))
    ink.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 6 else 0).getbbox()
    mark = max(bbox[2] - bbox[0], bbox[3] - bbox[1])

    legacy_t = crop_padded(ink, square_around(bbox, mark / LEGACY_FILL))
    legacy = Image.alpha_composite(
        Image.new('RGBA', legacy_t.size, (255, 255, 255, 255)), legacy_t)
    fg = crop_padded(ink, square_around(bbox, mark * 108 / ADAPTIVE_CONTENT_DP))

    for d, s in DENSITIES.items():
        legacy.resize((round(48 * s),) * 2, Image.LANCZOS).convert('RGB').save(
            f'{RES}/mipmap-{d}/ic_launcher.png', optimize=True)
        fg.resize((round(108 * s),) * 2, Image.LANCZOS).save(
            f'{RES}/mipmap-{d}/ic_launcher_foreground.png', optimize=True)

    legacy.resize((512, 512), Image.LANCZOS).save('assets/app_icon.png',
                                                  optimize=True)
    legacy.resize((256, 256), Image.LANCZOS).save(
        'windows/runner/resources/app_icon.ico',
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128),
               (256, 256)])

    if len(sys.argv) > 1:
        # Legacy square, adaptive in a circle mask, adaptive in a squircle-ish
        # rounded square — to eyeball the safe zone.
        sheet = Image.new('RGB', (740, 260), (225, 225, 225))
        sheet.paste(legacy.resize((216, 216)).convert('RGB'), (20, 22))
        tile = Image.alpha_composite(
            Image.new('RGBA', (324, 324), (255, 255, 255, 255)),
            fg.resize((324, 324), Image.LANCZOS)).crop((54, 54, 270, 270))
        for i, shape in enumerate(('circle', 'rounded')):
            m = Image.new('L', (216, 216), 0)
            if shape == 'circle':
                ImageDraw.Draw(m).ellipse((0, 0, 215, 215), fill=255)
            else:
                ImageDraw.Draw(m).rounded_rectangle((0, 0, 215, 215), 60,
                                                    fill=255)
            sheet.paste(tile.convert('RGB'), (262 + i * 240, 22), m)
        sheet.save(sys.argv[1])


if __name__ == '__main__':
    main()
