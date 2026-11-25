#!/usr/bin/env python3
import os
import sys

from PIL import Image, ImageChops, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER = os.path.dirname(HERE)

MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ICO_SIZES = [16, 32, 48, 64, 128, 256]
MAC_GRID = 824
MAC_RADIUS = 185
LOGO_SIZE = 512
LOGO_RADIUS = 113
MASKABLE_PAD = (36, 21, 48)


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], radius=radius, fill=255)
    out = im.copy()
    out.putalpha(ImageChops.multiply(out.getchannel("A"), mask))
    return out


def mac_master(src):
    art = src.resize((MAC_GRID, MAC_GRID), Image.NEAREST)
    art = rounded(art, MAC_RADIUS)
    master = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    master.paste(art, (100, 100), art)
    return master


def maskable(logo, size):
    inner = round(size * 2 / 3)
    small = logo.resize((inner, inner), Image.NEAREST)
    out = Image.new("RGBA", (size, size), MASKABLE_PAD + (255,))
    off = (size - inner) // 2
    out.paste(small, (off, off), small)
    return out


def main():
    src_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(FLUTTER, "assets", "images", "logo_source.png")
    src = Image.open(src_path).convert("RGBA")

    logo = rounded(src.resize((LOGO_SIZE, LOGO_SIZE), Image.NEAREST), LOGO_RADIUS)
    logo.save(os.path.join(FLUTTER, "assets", "images", "logo.png"))

    master = mac_master(src)
    for s in MAC_SIZES:
        master.resize((s, s), Image.NEAREST).save(
            os.path.join(FLUTTER, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset", f"app_icon_{s}.png"))

    logo.resize((64, 64), Image.NEAREST).save(os.path.join(FLUTTER, "web", "favicon.png"))
    for s in (192, 512):
        logo.resize((s, s), Image.NEAREST).save(os.path.join(FLUTTER, "web", "icons", f"Icon-{s}.png"))
        maskable(logo, s).save(os.path.join(FLUTTER, "web", "icons", f"Icon-maskable-{s}.png"))

    for dpi, s in ANDROID_SIZES.items():
        logo.resize((s, s), Image.NEAREST).save(
            os.path.join(FLUTTER, "android", "app", "src", "main", "res", f"mipmap-{dpi}", "ic_launcher.png"))

    master.save(os.path.join(FLUTTER, "windows", "runner", "resources", "app_icon.ico"),
                sizes=[(s, s) for s in ICO_SIZES])

    print("generated: logo.png, macos x7, web x5, android x5, windows ico")


if __name__ == "__main__":
    main()