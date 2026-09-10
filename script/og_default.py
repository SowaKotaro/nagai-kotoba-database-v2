# -*- coding: utf-8 -*-
"""public/og-default.png(1200x630)を描き直すための一回きりの道具。

   デザインは「しずか」の作法に従う(docs/design.md): 白地 / 太字なし / アクセント色なし /
   罫は 1px / 図はホーム最上部の印と同じ五十音円環。組みもホームと同じ格子で、
   横罫は画面端まで通し、縦罫3本(額の左右 + 袖と本体を分ける柱)は区画の全高に通す。

   実行: python3 script/og_default.py   (要 Pillow。日本語ゴシックと等幅を1本ずつ使う)
   単語ごとのカード生成(docs/issues.md)を作るときは、この体裁をそのまま ERB + SVG に移す。"""
import math
import os
from PIL import Image, ImageDraw, ImageFont

S = 3                      # スーパーサンプリング倍率(PIL の線は AA が無いので拡大して縮小する)
W, H = 1200, 630

TEXT          = (0x23, 0x2a, 0x31)
TEXT_MUTED    = (0x5f, 0x65, 0x68)
TEXT_SUBTLE   = (0x63, 0x68, 0x6c)
BORDER        = (0xdf, 0xe4, 0xec)
BORDER_STRONG = (0xc6, 0xcc, 0xd5)
WHITE         = (0xff, 0xff, 0xff)

# --font-sans / --font-mono(tokens.css)に載っている書体を、環境にある順で拾う。
SANS_CANDIDATES = [
    "/mnt/c/Windows/Fonts/NotoSansJP-VF.ttf",                    # WSL から見た Windows の Noto Sans JP
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf",       # IPAex ゴシック(最後の砦)
]
MONO_CANDIDATES = [
    "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
]

def pick(candidates):
    for path in candidates:
        if os.path.exists(path):
            return path
    raise SystemExit("書体が見つからない: " + " / ".join(candidates))

SANS, MONO = pick(SANS_CANDIDATES), pick(MONO_CANDIDATES)

def sans(size):
    font = ImageFont.truetype(SANS, int(round(size * S)))
    try:
        font.set_variation_by_name("Regular")   # 可変フォントでも太字にしない
    except OSError:
        pass
    return font

def mono(size):
    return ImageFont.truetype(MONO, int(round(size * S)))

# KanaRing.path("ナガイコトバノデータベース") の出力(viewBox 200)
RING = [(132.67, 175.21), (151.75, 36.39), (111.17, 18.76), (177.27, 72.54), (142.61, 170.06),
        (77.88, 178.96), (88.83, 181.24), (151.75, 163.61), (172.81, 137.73), (48.25, 163.61),
        (181.81, 105.60)]
RING_CENTER, RING_RADIUS, ARC_RADIUS = 100.0, 82.0, 90.0

img = Image.new("RGB", (W * S, H * S), WHITE)
draw = ImageDraw.Draw(img)

def px(value):
    return int(round(value * S))

def rule(x0, y0, x1, y1):
    """1px の細罫。縦横どちらか一方だけを引く。"""
    draw.rectangle([px(x0), px(y0), px(x1) + (S - 1 if x0 == x1 else 0),
                    px(y1) + (S - 1 if y0 == y1 else 0)], fill=BORDER)

def tracked(x, baseline, text, font, color, tracking):
    """字間(letter-spacing)を足しながら 1 文字ずつ描く。"""
    cursor = x * S
    for char in text:
        draw.text((cursor, baseline * S), char, font=font, fill=color, anchor="ls")
        cursor += font.getlength(char) + tracking * S

# ── 格子 ────────────────────────────────────────────────────────────────
FRAME_TOP, FRAME_BOTTOM = 66, 564
LEFT, PILLAR, RIGHT = 76, 430, 1124
rule(0, FRAME_TOP, W, FRAME_TOP)
rule(0, FRAME_BOTTOM, W, FRAME_BOTTOM)
for x in (LEFT, PILLAR, RIGHT):
    rule(x, FRAME_TOP, x, FRAME_BOTTOM)

# ── 左の袖: サイト名の読みの円環(ホーム最上部の印と同じ図)──────────────
RING_PX = 268
scale = RING_PX / 200.0
cx = (LEFT + PILLAR) / 2.0
cy = (FRAME_TOP + FRAME_BOTTOM) / 2.0

def ring_xy(point):
    return ((point[0] - RING_CENTER) * scale + cx, (point[1] - RING_CENTER) * scale + cy)

radius = RING_RADIUS * scale
draw.ellipse([px(cx - radius), px(cy - radius), px(cx + radius), px(cy + radius)],
             outline=BORDER_STRONG, width=px(1.4))
draw.line([tuple(px(v) for v in ring_xy(p)) for p in RING],
          fill=TEXT_SUBTLE, width=px(1.8), joint="curve")
for point in RING:                       # joint="curve" は端点を丸めないので自前で足す
    x0, y0 = ring_xy(point)
    draw.ellipse([px(x0 - 0.9), px(y0 - 0.9), px(x0 + 0.9), px(y0 + 0.9)], fill=TEXT_SUBTLE)
start_x, start_y = ring_xy(RING[0])      # 始点(ナ)
dot = 2.6 * scale
draw.ellipse([px(start_x - dot), px(start_y - dot), px(start_x + dot), px(start_y + dot)],
             fill=TEXT_MUTED)

# 円の外側を弧を描いて回る英字(ホームの印と同じ。真上を中心に時計回り)
ARC = "NAGAI KOTOBA DATABASE"
arc_font = mono(11 * scale)
arc_tracking = 1.4 * scale
arc_radius = ARC_RADIUS * scale
advances = [arc_font.getlength(c) / S + arc_tracking for c in ARC]
offset = -(sum(advances) - arc_tracking) / 2.0
for char, advance in zip(ARC, advances):
    theta = (offset + (advance - arc_tracking) / 2.0) / arc_radius   # 弧長 → 角度(rad)
    bx = cx + arc_radius * math.sin(theta)
    by = cy - arc_radius * math.cos(theta)
    tile = Image.new("RGBA", (px(40), px(40)), (0, 0, 0, 0))
    ImageDraw.Draw(tile).text((px(20), px(20)), char, font=arc_font,
                              fill=TEXT_SUBTLE + (255,), anchor="ms")
    tile = tile.rotate(-math.degrees(theta), resample=Image.BICUBIC)
    img.paste(tile, (round(bx * S) - px(20), round(by * S) - px(20)), tile)
    offset += advance

# ── 右の本体: 見出し → 説明 → 罫 → 標識 ────────────────────────────────
BODY = 474
title_font, lead_font, label_font = sans(54), sans(21), mono(19)
TITLE = "長い言葉のデータベース"
LEAD  = "日本語の長い言葉を、読み・文字・韻・ジャンルから眺める"
LABEL_1, LABEL_2 = "NAGAI-KOTOBA-DATABASE.JP", "READING / 10+ CHARACTERS"

LEAD_Y, RULE_Y, LABEL_1_Y, LABEL_2_Y = 62, 108, 152, 192

# ベースラインではなく字面(インク)の上端と下端で中心を取る。でないと見た目が下へ寄る。
ink_top = title_font.getbbox(TITLE, anchor="ls")[1] / S
ink_bottom = LABEL_2_Y + label_font.getbbox(LABEL_2, anchor="ls")[3] / S
base = cy - (ink_top + ink_bottom) / 2.0

tracked(BODY, base, TITLE, title_font, TEXT, 54 * 0.03)
tracked(BODY, base + LEAD_Y, LEAD, lead_font, TEXT_MUTED, 21 * 0.03)
rule(BODY, base + RULE_Y, RIGHT, base + RULE_Y)
tracked(BODY, base + LABEL_1_Y, LABEL_1, label_font, TEXT_SUBTLE, 19 * 0.04)
tracked(BODY, base + LABEL_2_Y, LABEL_2, label_font, TEXT_SUBTLE, 19 * 0.04)

OUT = os.path.join(os.path.dirname(__file__), "..", "public", "og-default.png")
img.resize((W, H), Image.LANCZOS).save(os.path.normpath(OUT))
