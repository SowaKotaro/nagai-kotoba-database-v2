# -*- coding: utf-8 -*-
"""public/og-default.png(1200x630)を描き直すための一回きりの道具。

   デザインは「しずか」の作法に従う(docs/design.md §5.1): 地と墨 / 太字はサイト名だけ / アクセント色なし /
   罫は 1px / 図はホーム最上部の印と同じ五十音円環(線は墨、円は図の灰)。組みは
   ホームを 1 枚の紙に組んでいた頃の格子のままで、横罫は画面端まで通し、
   縦罫3本(額の左右 + 袖と本体を分ける柱)は区画の全高に通す。

   実行: python3 script/og_default.py   (要 Pillow。日本語ゴシックと等幅を1本ずつ使う)
   単語ごとの共有カードは、この体裁を ERB + SVG に移して app/views/share_cards/word.svg.erb(WordShareCard)で描いている。
   格子・色・書体を変えるときは両方をそろえる。"""
import math
import os
from PIL import Image, ImageDraw, ImageFont

S = 3                      # スーパーサンプリング倍率(PIL の線は AA が無いので拡大して縮小する)
W, H = 1200, 630

# ライトのトークン(tokens.css)と同値。画像は見る人のテーマに追従できないので、地の 1 枚に決める。
BG            = (0xfa, 0xfa, 0xfa)   # --bg
TEXT          = (0x2f, 0x27, 0x25)   # --text
TEXT_MUTED    = (0x5c, 0x4e, 0x4a)   # --text-muted
TEXT_SUBTLE   = (0x6a, 0x60, 0x5c)   # --text-subtle
BORDER        = (0xe4, 0xe3, 0xe0)   # --border
CHART         = (0x8f, 0x86, 0x82)   # --chart(印の円)

# 字間(em)。単語ごとのカード(WordShareCard の SURFACE_TRACKING / READING_TRACKING / LABEL_TRACKING)と同じ値。
# サイトは palt で詰めてから開けるが、カードは詰めずに組むので、同じ幅になる字間にしてある。
TITLE_TRACKING, LEAD_TRACKING, LABEL_TRACKING = 0.0, -0.03, 0.04

# --font-sans / --font-mono(tokens.css)に載っている書体を、環境にある順で拾う。
# 和文は (Regular, Bold) の組。可変フォントは 1 つのファイルから太さを選ぶ。
SANS_CANDIDATES = [
    ("/mnt/c/Windows/Fonts/NotoSansJP-VF.ttf",) * 2,             # WSL から見た Windows の Noto Sans JP
    ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",    # 本番の単語カードと同じ書体
     "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"),
    ("/usr/share/fonts/truetype/fonts-japanese-gothic.ttf",) * 2, # IPAex ゴシック(最後の砦。太字は持たない)
]
MONO_CANDIDATES = [
    "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
]

def pick(candidates):
    for path in candidates:
        if os.path.exists(path[0] if isinstance(path, tuple) else path):
            return path
    raise SystemExit("書体が見つからない: " + " / ".join(map(str, candidates)))

SANS, MONO = pick(SANS_CANDIDATES), pick(MONO_CANDIDATES)

def sans(size, bold=False):
    """太字は Bold(700)。単語カードを焼く本番の書体が持つ、いちばん太い字に合わせる。"""
    font = ImageFont.truetype(SANS[1] if bold else SANS[0], int(round(size * S)))
    try:
        font.set_variation_by_name("Bold" if bold else "Regular")
    except OSError:
        pass                                     # 可変フォントでなければ、ファイルが太さを決める
    return font

def mono(size):
    return ImageFont.truetype(MONO, int(round(size * S)))

# KanaRing.path("ナガイコトバノデータベース") の出力(viewBox 200)
RING = [(132.67, 175.21), (151.75, 36.39), (111.17, 18.76), (177.27, 72.54), (142.61, 170.06),
        (77.88, 178.96), (88.83, 181.24), (151.75, 163.61), (172.81, 137.73), (48.25, 163.61),
        (181.81, 105.60)]
RING_CENTER, RING_RADIUS, ARC_RADIUS = 100.0, 82.0, 90.0

img = Image.new("RGB", (W * S, H * S), BG)
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
# 色と太さの比も印(.ring-art--mark)に合わせる: 線と始点は墨、円は図の灰、外周の英字は --text-muted。
# 印は 172px に線 1.5px・円 1px なので、268px のここでは 1.5 倍と 1.4 倍にする。
RING_PX = 268
LINE_WIDTH, CIRCLE_WIDTH = 2.25, 1.4
scale = RING_PX / 200.0
cx = (LEFT + PILLAR) / 2.0
cy = (FRAME_TOP + FRAME_BOTTOM) / 2.0

def ring_xy(point):
    return ((point[0] - RING_CENTER) * scale + cx, (point[1] - RING_CENTER) * scale + cy)

radius = RING_RADIUS * scale
draw.ellipse([px(cx - radius), px(cy - radius), px(cx + radius), px(cy + radius)],
             outline=CHART, width=px(CIRCLE_WIDTH))
draw.line([tuple(px(v) for v in ring_xy(p)) for p in RING],
          fill=TEXT, width=px(LINE_WIDTH), joint="curve")
cap = LINE_WIDTH / 2
for point in RING:                       # joint="curve" は端点を丸めないので自前で足す
    x0, y0 = ring_xy(point)
    draw.ellipse([px(x0 - cap), px(y0 - cap), px(x0 + cap), px(y0 + cap)], fill=TEXT)
start_x, start_y = ring_xy(RING[0])      # 始点(ナ)
dot = 2.6 * scale
draw.ellipse([px(start_x - dot), px(start_y - dot), px(start_x + dot), px(start_y + dot)],
             fill=TEXT)

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
                              fill=TEXT_MUTED + (255,), anchor="ms")
    tile = tile.rotate(-math.degrees(theta), resample=Image.BICUBIC)
    img.paste(tile, (round(bx * S) - px(20), round(by * S) - px(20)), tile)
    offset += advance

# ── 右の本体: 見出し → 説明 → 罫 → 標識 ────────────────────────────────
BODY = 474
title_font, lead_font, label_font = sans(54, bold=True), sans(21), mono(19)
TITLE = "長い言葉のデータベース"
LEAD  = "日本語の長い言葉を、読み・文字・韻・ジャンルから眺める"
LABEL_1, LABEL_2 = "NAGAI-KOTOBA-DATABASE.JP", "READING / 10+ CHARACTERS"

LEAD_Y, RULE_Y, LABEL_1_Y, LABEL_2_Y = 62, 108, 152, 192

# ベースラインではなく字面(インク)の上端と下端で中心を取る。でないと見た目が下へ寄る。
ink_top = title_font.getbbox(TITLE, anchor="ls")[1] / S
ink_bottom = LABEL_2_Y + label_font.getbbox(LABEL_2, anchor="ls")[3] / S
base = cy - (ink_top + ink_bottom) / 2.0

tracked(BODY, base, TITLE, title_font, TEXT, 54 * TITLE_TRACKING)
tracked(BODY, base + LEAD_Y, LEAD, lead_font, TEXT_MUTED, 21 * LEAD_TRACKING)
rule(BODY, base + RULE_Y, RIGHT, base + RULE_Y)
tracked(BODY, base + LABEL_1_Y, LABEL_1, label_font, TEXT_SUBTLE, 19 * LABEL_TRACKING)
tracked(BODY, base + LABEL_2_Y, LABEL_2, label_font, TEXT_SUBTLE, 19 * LABEL_TRACKING)

OUT = os.path.join(os.path.dirname(__file__), "..", "public", "og-default.png")
img.resize((W, H), Image.LANCZOS).save(os.path.normpath(OUT))
