from PIL import Image, ImageDraw, ImageFont

S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size, c0, c1):
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = lerp(c0, c1, (x + y) / (2 * (size - 1)))
    return img


def rounded(size, radius, fill):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=fill)
    return img


def soft_shadow(size, box, radius, blur, color, offset):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    d.rounded_rectangle(
        [x0 + offset[0], y0 + offset[1], x1 + offset[0], y1 + offset[1]],
        radius=radius, fill=color)
    from PIL import ImageFilter
    return img.filter(ImageFilter.GaussianBlur(blur))


def vgradient_tile(size, radius, c0, c1):
    grad = Image.new('RGBA', (size, size))
    px = grad.load()
    for y in range(size):
        c = lerp(c0, c1, y / (size - 1)) + (255,)
        for x in range(size):
            px[x, y] = c
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255)
    grad.putalpha(mask)
    return grad


bg = diagonal_gradient(S, (64, 176, 122), (21, 104, 71)).convert('RGBA')

page_back = rounded(470, 64, (214, 236, 224, 255))
page_front = rounded(470, 64, (250, 253, 251, 255))
d = ImageDraw.Draw(page_front)
for i, y in enumerate((150, 230, 310)):
    w = 300 if i < 2 else 210
    d.rounded_rectangle([70, y, 70 + w, y + 26], radius=13,
                        fill=(163, 209, 186, 255))

art = bg.copy()
art.alpha_composite(soft_shadow(S, (470, 170, 940, 640), 64, 24, (8, 54, 36, 90), (0, 18)))
art.alpha_composite(page_back, (500, 150))
art.alpha_composite(soft_shadow(S, (430, 210, 900, 680), 64, 24, (8, 54, 36, 110), (0, 18)))
art.alpha_composite(page_front, (430, 210))

tile = vgradient_tile(400, 92, (35, 122, 84), (17, 82, 56))
art.alpha_composite(soft_shadow(S, (120, 490, 520, 890), 92, 30, (6, 44, 29, 140), (0, 24)))
art.alpha_composite(tile, (120, 490))

font = ImageFont.truetype('assets/fonts/Inter-700.ttf', 280)
d = ImageDraw.Draw(art)
bbox = d.textbbox((0, 0), 'N', font=font)
w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
d.text((120 + (400 - w) / 2 - bbox[0], 490 + (400 - h) / 2 - bbox[1]), 'N',
       font=font, fill=(255, 255, 255, 255))

art.save('assets/images/logo.png')

canvas = Image.new('RGBA', (S, S), (0, 0, 0, 0))
mask = Image.new('L', (824, 824), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, 823, 823], radius=184, fill=255)
canvas.paste(art.resize((824, 824), Image.LANCZOS), (100, 100), mask)
out = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
for s in (16, 32, 64, 128, 256, 512, 1024):
    canvas.resize((s, s), Image.LANCZOS).save(f'{out}/app_icon_{s}.png')
for s, name in ((192, 'Icon-192'), (512, 'Icon-512'),
                (192, 'Icon-maskable-192'), (512, 'Icon-maskable-512')):
    art.resize((s, s), Image.LANCZOS).save(f'web/icons/{name}.png')
art.resize((512, 512), Image.LANCZOS).save('web/favicon.png')
art.resize((256, 256), Image.LANCZOS).save(
    'windows/runner/resources/app_icon.ico',
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
for folder, s in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                  ('xxhdpi', 144), ('xxxhdpi', 192)):
    art.resize((s, s), Image.LANCZOS).save(
        f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
print('fluent vector icon deployed')