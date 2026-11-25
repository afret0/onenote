import os
from PIL import Image

N = 32
PAL = {
    'G1': (46, 125, 91),
    'P1': (119, 25, 170),
    'GL': (54, 146, 105),
    'GD': (38, 106, 77),
    'DP': (27, 79, 56),
    'M': (233, 243, 237),
    'K': (16, 20, 24),
    'W': (255, 255, 255),
    'C': (240, 234, 220),
    'B': (125, 211, 252),
    'G': (148, 163, 184),
    'g': (203, 213, 225),
    'P': (236, 72, 153),
    'Y': (250, 204, 21),
    'Y2': (253, 224, 71),
    'O': (245, 158, 11),
    'F': (226, 232, 240),
    'D': (31, 89, 64),
    'R': (239, 68, 68),
    'T': (233, 196, 152),
    'E': (244, 163, 181),
    'g3': (71, 85, 105),
}
BGKEYS = {'G1', 'GL', 'GD', 'DP', 'M'}

OUT = os.path.expanduser(
    '~/.copilot/session-state/74e9563e-5810-4ddf-aa92-5e6c66e32099/files/icon_candidates')
os.makedirs(OUT, exist_ok=True)


class Grid:
    def __init__(self, bgfn):
        self.bgfn = bgfn
        self.px = [[bgfn(x, y) for x in range(N)] for y in range(N)]

    def s(self, x, y, c):
        if 0 <= x < N and 0 <= y < N:
            self.px[y][x] = c

    def r(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.s(x, y, c)

    def outline(self, cells):
        border = set()
        cs = set(cells)
        for x, y in cs:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if (nx, ny) not in cs and 0 <= nx < N and 0 <= ny < N:
                        if self.px[ny][nx] in BGKEYS:
                            border.add((nx, ny))
        for x, y in border:
            self.s(x, y, 'K')

    def image(self):
        img = Image.new('RGB', (N, N))
        img.putdata([PAL[c] for row in self.px for c in row])
        return img.resize((512, 512), Image.NEAREST)


def mascot_body(g, feet=True):
    dx, dy = 2, -2

    def s(x, y, c):
        g.s(x + dx, y + dy, c)

    def r(x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                s(x, y, c)

    r(7, 6, 24, 26, 'K')
    r(8, 7, 23, 25, 'W')
    r(23, 7, 23, 25, 'C')
    r(8, 25, 23, 25, 'C')
    for y in range(6, 11):
        for x in range(20, 25):
            ddx, ddy = x - 20, y - 6
            if ddx > ddy:
                s(x, y, g.bgfn(x + dx, y + dy))
            elif ddx == ddy:
                s(x, y, 'K')
            else:
                s(x, y, 'F')
    if feet:
        r(11, 27, 14, 29, 'K')
        r(12, 28, 13, 28, 'W')
        r(18, 27, 21, 29, 'K')
        r(19, 28, 20, 28, 'W')
    for y0 in (9, 13, 17, 21):
        r(4, y0, 7, y0 + 1, 'K')
        r(5, y0, 6, y0 + 1, 'G')
        s(5, y0, 'g')
    return s, r


def face_classic(s, r):
    for y in (10, 13, 16, 22, 24):
        r(10, y, 21, y, 'B')
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


def face_happy(s, r):
    for y in (9, 11, 22, 24):
        r(10, y, 21, y, 'B')
    for x, y in [(11, 15), (12, 14), (13, 14), (14, 15),
                 (17, 15), (18, 14), (19, 14), (20, 15)]:
        s(x, y, 'K')
    s(14, 18, 'K')
    s(15, 19, 'K')
    s(16, 19, 'K')
    s(17, 18, 'K')
    r(9, 17, 10, 18, 'P')
    r(21, 17, 22, 18, 'P')


def face_round(s, r):
    for y in (9, 11, 22, 24):
        r(10, y, 21, y, 'B')
    r(11, 13, 13, 15, 'K')
    r(18, 13, 20, 15, 'K')
    s(11, 13, 'W')
    s(18, 13, 'W')
    s(13, 18, 'K')
    s(18, 18, 'K')
    r(14, 19, 17, 19, 'K')
    r(9, 17, 10, 18, 'P')
    r(21, 17, 22, 18, 'P')


def draw_mascot(g, face):
    s, r = mascot_body(g)
    face(s, r)


BOLT = [
    (26, 1), (27, 1), (28, 1),
    (25, 2), (26, 2), (27, 2), (28, 2),
    (24, 3), (25, 3), (26, 3), (27, 3),
    (23, 4), (24, 4), (25, 4), (26, 4), (27, 4), (28, 4), (29, 4),
    (25, 5), (26, 5), (27, 5), (28, 5), (29, 5),
    (26, 6), (27, 6), (28, 6),
    (25, 7), (26, 7), (27, 7),
    (24, 8), (25, 8), (26, 8),
    (23, 9), (24, 9),
]


def draw_bolt(g):
    cells = set(BOLT)
    for x, y in BOLT:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) not in cells:
                    g.s(x + dx, y + dy, 'K')
    for x, y in BOLT:
        g.s(x, y, 'Y')
    for x, y in [(29, 4), (29, 5), (28, 6), (27, 7), (26, 8), (24, 9)]:
        g.s(x, y, 'O')
    for x, y in [(26, 1), (25, 2), (24, 3)]:
        g.s(x, y, 'W')


def draw_notebook(g):
    s, r = mascot_body(g, feet=False)
    for y in (10, 13, 16, 19, 22):
        r(10, y, 21, y, 'B')
    tail = [(x, y) for x in range(20, 23) for y in range(25, 28)]
    for x, y in tail:
        g.s(x, y, 'R')
    g.outline(tail)
    g.s(21, 27, g.bgfn(21, 27))


def draw_pencil(g):
    cells = []
    for y in range(N):
        for x in range(N):
            d, p = x - y, x + y - 31
            if -19 <= d <= -17:
                w = 0 if d <= -18 else 1
                c = 'g3'
            elif -16 <= d <= -13:
                w = {-16: 1, -15: 2, -14: 2, -13: 3}[d]
                c = 'T'
            elif -12 <= d <= 10:
                w = 3
                c = 'Y2' if p <= -2 else 'O' if p >= 2 else 'Y'
            elif 11 <= d <= 13:
                w = 3
                c = 'g' if d % 2 == 0 else 'G'
            elif 14 <= d <= 17:
                w = 3
                c = 'E'
            elif d == 18:
                w = 2
                c = 'E'
            else:
                continue
            if abs(p) <= w:
                g.s(x, y, c)
                cells.append((x, y))
    g.outline(cells)


def draw_nib(g):
    rows = {5: 3, 6: 3, 7: 4, 8: 5, 9: 6, 10: 6, 11: 6, 12: 6,
            13: 6, 14: 5, 15: 5, 16: 4, 17: 4, 18: 3, 19: 3,
            20: 2, 21: 2, 22: 1, 23: 1, 24: 1}
    cells = []
    for y, hw in rows.items():
        for x in range(16 - hw, 15 + hw + 1):
            c = 'O' if y <= 6 or x in (16 - hw, 15 + hw) else 'Y'
            g.s(x, y, c)
            cells.append((x, y))
    g.outline(cells)
    g.r(15, 12, 16, 13, 'K')
    g.r(15, 15, 16, 23, 'K')


def draw_n(g, bgkey):
    fill = 'G1' if bgkey == 'mint' else 'W'
    cells = []

    def put(x0, y0, x1, y1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                g.s(x, y, fill)
                cells.append((x, y))

    put(8, 7, 11, 24)
    put(20, 7, 23, 24)
    for y in range(7, 25):
        x0 = 11 + (y - 7) * 9 // 17
        put(x0, y, x0 + 2, y)
    g.outline(cells)


def draw_check(g):
    g.r(7, 6, 24, 27, 'K')
    g.r(8, 7, 23, 26, 'W')
    g.r(23, 7, 23, 26, 'C')
    g.r(8, 26, 23, 26, 'C')
    for x0 in (10, 14, 18, 22):
        g.r(x0, 4, x0 + 1, 6, 'K')
        g.s(x0, 5, 'g')
    for y in (10, 13):
        g.r(10, y, 21, y, 'B')
    for x, y in [(11, 19), (12, 20), (13, 21), (14, 22), (15, 21),
                 (16, 20), (17, 19), (18, 18), (19, 17), (20, 16), (21, 15)]:
        g.r(x, y, x + 1, y + 1, 'G1')


def draw_sticky(g):
    cells = []
    for y in range(6, 27):
        for x in range(6, 27):
            in_front = 6 <= x <= 22 and 6 <= y <= 22
            in_back = 11 <= x <= 26 and 11 <= y <= 26
            if not (in_front or in_back):
                continue
            cells.append((x, y))
            if in_front:
                g.s(x, y, 'Y')
            else:
                g.s(x, y, 'O')
    g.outline(cells)
    g.r(23, 11, 23, 26, 'K')
    g.r(11, 23, 26, 23, 'K')
    for y in (10, 13, 16):
        g.r(9, y, 19, y, 'O')


def draw_book(g):
    cells = []
    for x in range(4, 28):
        if x in (15, 16):
            continue
        mx = x if x < 15 else 31 - x
        top = 10 if mx <= 7 else 9 if mx <= 11 else 8
        for y in range(top, 25):
            g.s(x, y, 'C' if y == 24 else 'W')
            cells.append((x, y))
    for y in (13, 16, 19, 22):
        g.r(6, y, 13, y, 'B')
        g.r(18, y, 25, y, 'B')
    g.r(15, 8, 16, 25, 'K')
    for x in range(3, 29):
        for y in (25, 26):
            g.s(x, y, 'D')
            cells.append((x, y))
    g.outline(cells)


def draw_journal(g):
    cells = []
    for y in range(5, 27):
        for x in range(7, 27):
            if x <= 23:
                c = 'GL' if x == 8 else 'D'
            else:
                c = 'g' if x == 25 else 'W'
            g.s(x, y, c)
            cells.append((x, y))
    g.outline(cells)
    g.r(19, 5, 20, 26, 'K')
    g.r(10, 9, 16, 13, 'W')
    g.r(11, 10, 15, 10, 'B')
    g.r(11, 12, 15, 12, 'B')
    g.r(11, 27, 13, 29, 'R')
    g.s(12, 29, g.bgfn(12, 29))
    g.r(10, 27, 10, 29, 'K')
    g.r(14, 27, 14, 29, 'K')
    g.r(11, 30, 13, 30, 'K')


def draw_feather(g):
    cells = []
    for y in range(N):
        for x in range(N):
            d, p = x - y, x + y - 31
            if -17 <= d <= -15:
                if p in (-1, 0):
                    g.s(x, y, 'Y')
                    cells.append((x, y))
                continue
            if not (-14 <= d <= 12):
                continue
            w = max(1, 4 - max(0, abs(d) - 6) // 2)
            if not (-w <= p <= w - 1):
                continue
            if d % 3 == 0 and p in (-w, -w + 1):
                continue
            if d % 3 == 1 and p == w - 1:
                continue
            c = 'G' if p == 0 else 'g' if p >= 2 else 'W'
            g.s(x, y, c)
            cells.append((x, y))
    g.outline(cells)


BGS = [
    ('green', '主题绿', lambda x, y: 'G1'),
    ('duo', '双色绿', lambda x, y: 'GL' if x + y < 31 else 'GD' if x + y > 31 else ('GL' if x % 2 else 'GD')),
    ('deep', '深绿', lambda x, y: 'DP'),
    ('mint', '浅薄荷', lambda x, y: 'M'),
    ('purple', 'OneNote紫', lambda x, y: 'P1'),
]

SUBJECTS = [
    ('眯眯笑眼本', lambda g, bk: draw_mascot(g, face_happy)),
    ('圆豆眼本', lambda g, bk: draw_mascot(g, face_round)),
    ('经典方眼本', lambda g, bk: draw_mascot(g, face_classic)),
    ('螺旋本书签', lambda g, bk: draw_notebook(g)),
    ('大铅笔', lambda g, bk: draw_pencil(g)),
    ('钢笔尖', lambda g, bk: draw_nib(g)),
    ('像素N', lambda g, bk: draw_n(g, bk)),
    ('顶圈本对勾', lambda g, bk: draw_check(g)),
    ('便利贴', lambda g, bk: draw_sticky(g)),
    ('摊开的书', lambda g, bk: draw_book(g)),
    ('手账本', lambda g, bk: draw_journal(g)),
    ('羽毛笔', lambda g, bk: draw_feather(g)),
]

cards = []
idx = 0


def emit(label, bgfn, draw):
    global idx
    idx += 1
    g = Grid(bgfn)
    draw(g)
    name = f'c{idx:02d}.png'
    g.image().save(os.path.join(OUT, name))
    cards.append((idx, name, label))


for slabel, sfn in SUBJECTS:
    for bkey, blabel, bgfn in BGS:
        emit(f'{slabel} · {blabel}', bgfn, lambda g, f=sfn, k=bkey: f(g, k))

emit('眯眯笑眼本 · 闪电 · 主题绿', BGS[0][2],
     lambda g: (draw_mascot(g, face_happy), draw_bolt(g)))
emit('圆豆眼本 · 闪电 · 主题绿', BGS[0][2],
     lambda g: (draw_mascot(g, face_round), draw_bolt(g)))

html = ['<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8">',
        '<title>onenote 图标候选</title><style>',
        'body{background:#141416;color:#e8e8ea;font-family:-apple-system,"PingFang SC",sans-serif;margin:0;padding:28px}',
        'h1{font-size:20px;margin:0 0 6px} p.tip{color:#9a9aa2;font-size:13px;margin:0 0 22px}',
        '.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:16px}',
        '.card{background:#232327;border-radius:14px;padding:14px;text-align:center}',
        '.num{display:inline-block;background:#2E7D5B;color:#fff;border-radius:8px;padding:2px 10px;font-weight:700;font-size:14px;margin-bottom:10px}',
        '.big{width:144px;height:144px;border-radius:32px;image-rendering:pixelated;display:block;margin:0 auto}',
        '.dock{background:#1c1c1e;border-radius:10px;margin-top:12px;padding:8px 0;display:flex;justify-content:center;align-items:flex-end;gap:10px}',
        '.s40{width:40px;height:40px;border-radius:9px;image-rendering:pixelated}',
        '.s24{width:24px;height:24px;border-radius:6px;image-rendering:pixelated}',
        '.lbl{font-size:12px;color:#b8b8c0;margin-top:10px}',
        '</style></head><body>',
        '<h1>onenote 图标候选 · 共 %d 张</h1>' % idx,
        '<p class="tip">大图看细节，下方深色条模拟 Dock 里的实际大小。回复编号即可。</p>',
        '<div class="grid">']
for i, name, label in cards:
    html.append(
        f'<div class="card"><span class="num">#{i:02d}</span>'
        f'<img class="big" src="{name}">'
        f'<div class="dock"><img class="s40" src="{name}"><img class="s24" src="{name}"></div>'
        f'<div class="lbl">{label}</div></div>')
html.append('</div></body></html>')
with open(os.path.join(OUT, 'index.html'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(html))
print(f'{idx} candidates -> {OUT}')