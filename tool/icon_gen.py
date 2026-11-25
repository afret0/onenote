from PIL import Image, ImageDraw

N = 32
PAL = {
    'GL': (140, 52, 194),
    'GD': (101, 17, 146),
    'K': (16, 20, 24),
    'W': (255, 255, 255),
}


def bgfn(x, y):
    if x + y < 31:
        return 'GL'
    if x + y > 31:
        return 'GD'
    return 'GL' if x % 2 else 'GD'


px = [[bgfn(x, y) for x in range(N)] for y in range(N)]


def s(x, y, c):
    if 0 <= x < N and 0 <= y < N:
        px[y][x] = c


cells = []


def put(x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            s(x, y, 'W')
            cells.append((x, y))


put(8, 7, 11, 24)
put(20, 7, 23, 24)
for y in range(7, 25):
    x0 = 11 + (y - 7) * 9 // 17
    put(x0, y, x0 + 2, y)

cs = set(cells)
border = set()
for x, y in cs:
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            nx, ny = x + dx, y + dy
            if (nx, ny) not in cs and 0 <= nx < N and 0 <= ny < N:
                if px[ny][nx] in ('GL', 'GD'):
                    border.add((nx, ny))
for x, y in border:
    s(x, y, 'K')

art = Image.new('RGB', (N, N))
art.putdata([PAL[c] for row in px for c in row])
art = art.resize((1024, 1024), Image.NEAREST).convert('RGBA')
art.save('assets/images/logo.png')

margined = Image.new('RGB', (N + 4, N + 4))
margined.putdata([PAL[bgfn(x - 2, y - 2)]
                  for y in range(N + 4) for x in range(N + 4)])
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
print('pixel N icon deployed')
