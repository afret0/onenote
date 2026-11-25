from PIL import Image, ImageDraw, ImageFilter

N = 32
PAL = {
    'bg': (46, 125, 91),
    'K': (16, 20, 24),
    'W': (255, 255, 255),
    'C': (240, 234, 220),
    'B': (125, 211, 252),
    'G': (148, 163, 184),
    'g': (203, 213, 225),
    'P': (236, 72, 153),
    'Y': (250, 204, 21),
    'O': (245, 158, 11),
    'F': (226, 232, 240),
}
px = [['bg'] * N for _ in range(N)]


def s(x, y, c):
    x, y = x + 2, y - 2
    if 0 <= x < N and 0 <= y < N:
        px[y][x] = c


def r(x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            s(x, y, c)


r(7, 6, 24, 26, 'K')
r(8, 7, 23, 25, 'W')
r(23, 7, 23, 25, 'C')
r(8, 25, 23, 25, 'C')
for y in (10, 13, 16, 22, 24):
    r(10, y, 21, y, 'B')
for y in range(6, 11):
    for x in range(20, 25):
        dx, dy = x - 20, y - 6
        if dx > dy:
            s(x, y, 'bg')
        elif dx == dy:
            s(x, y, 'K')
        else:
            s(x, y, 'F')
r(11, 14, 14, 17, 'K')
r(18, 14, 21, 17, 'K')
r(11, 14, 12, 15, 'W')
r(18, 14, 19, 15, 'W')
s(14, 19, 'K')
s(15, 20, 'K')
s(16, 20, 'K')
s(17, 20, 'K')
s(18, 19, 'K')
r(9, 18, 10, 19, 'P')
r(21, 18, 22, 19, 'P')
r(11, 27, 14, 29, 'K')
r(12, 28, 13, 28, 'W')
r(18, 27, 21, 29, 'K')
r(19, 28, 20, 28, 'W')
for y0 in (9, 13, 17, 21):
    r(4, y0, 7, y0 + 1, 'K')
    r(5, y0, 6, y0 + 1, 'G')
    s(5, y0, 'g')
art = Image.new('RGB', (N, N))
art.putdata([PAL[c] for row in px for c in row])
art = art.resize((1024, 1024), Image.NEAREST).convert('RGBA')
art.save('assets/images/logo.png')

margined = Image.new('RGB', (N + 4, N + 4), PAL['bg'])
margined.paste(art.resize((N, N), Image.NEAREST), (2, 2))
big = margined.resize((1152, 1152), Image.NEAREST).convert('RGBA')
canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
mask = Image.new('L', (824, 824), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, 823, 823], radius=184, fill=255)
canvas.paste(big.resize((824, 824), Image.LANCZOS), (100, 100), mask)
out = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
for size in (16, 32, 64, 128, 256, 512, 1024):
    canvas.resize((size, size), Image.LANCZOS).save(f'{out}/app_icon_{size}.png')
for size, name in ((192, 'Icon-192'), (512, 'Icon-512')):
    art.resize((size, size), Image.NEAREST).save(f'web/icons/{name}.png')
for size, name in ((192, 'Icon-maskable-192'), (512, 'Icon-maskable-512')):
    big.resize((size, size), Image.LANCZOS).save(f'web/icons/{name}.png')
art.resize((512, 512), Image.NEAREST).save('web/favicon.png')
art.resize((256, 256), Image.NEAREST).save(
    'windows/runner/resources/app_icon.ico',
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
for folder, size in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                     ('xxhdpi', 144), ('xxxhdpi', 192)):
    art.resize((size, size), Image.NEAREST).save(
        f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
print('pixel grid icon deployed')
