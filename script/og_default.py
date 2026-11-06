# -*- coding: utf-8 -*-
"""public/og-default.png(1200x630)を描き直すための一回きりの道具。

   デザインは「しずか」の作法に従う(docs/design.md §5.1): 地と墨 / 太字はサイト名だけ / アクセント色なし。
   組みは、長い言葉の壁(公開している長い言葉を淡い墨で何行も流した背景)の上に、今のホームの看板
   (印〈五十音円環〉→ サイト名 → 説明 → 検索バー)を 1 枚の札(白の面＋墨の枠＋角)にまとめて中央に置く。
   検索バーは本物と同じ作り(白の面＋墨の枠＋角、墨の面の「検索」ボタン)。
   壁の語と並べ方は config/share_card_wall.json(単語ごとのカードの背景 ShareCardWall と共通)。
   英字の標識と罫は置かない(サイトでも英字の標識をやめた流れと、SNS のサムネイルでは細かい字が読めないため。2026-11-06)。
   画像は縮小されて表示されるので、サイトの 1px・角 8px は 2px・角 12px に太らせてある。
   (ホームを 1 枚の紙に組んでいた〜2026-11-03 は、左の袖に印・右の本体に文字を置く淡い格子だった。)

   実行: python3 script/og_default.py   (要 Pillow。日本語ゴシックを 1 本使う)
   単語ごとの共有カードは、色と書体と札の作りと壁をこれにそろえて ERB + SVG で描いている
   (app/views/share_cards/word.svg.erb、WordShareCard)。色・書体・枠・壁を変えるときは両方をそろえる。"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

S = 3                      # スーパーサンプリング倍率(PIL の線は AA が無いので拡大して縮小する)
W, H = 1200, 630

# ライトのトークン(tokens.css)と同値。画像は見る人のテーマに追従できないので、地の 1 枚に決める。
BG            = (0xfa, 0xfa, 0xfa)   # --bg
TEXT          = (0x2f, 0x27, 0x25)   # --text
TEXT_MUTED    = (0x5c, 0x4e, 0x4a)   # --text-muted
TEXT_SUBTLE   = (0x6a, 0x60, 0x5c)   # --text-subtle
CHART         = (0x8f, 0x86, 0x82)   # --chart(印の円)

# 字間(em)。単語ごとのカード(WordShareCard の SURFACE_TRACKING / READING_TRACKING)と同じ値。
# サイトは palt で詰めてから開けるが、カードは詰めずに組むので、同じ幅になる字間にしてある。
TITLE_TRACKING, LEAD_TRACKING = 0.0, -0.03

# --font-sans(tokens.css)に載っている書体を、環境にある順で拾う。
# 和文は (Regular, Bold) の組。可変フォントは 1 つのファイルから太さを選ぶ。
SANS_CANDIDATES = [
    ("/mnt/c/Windows/Fonts/NotoSansJP-VF.ttf",) * 2,             # WSL から見た Windows の Noto Sans JP
    ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",    # 本番の単語カードと同じ書体
     "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"),
    ("/usr/share/fonts/truetype/fonts-japanese-gothic.ttf",) * 2, # IPAex ゴシック(最後の砦。太字は持たない)
]

def pick(candidates):
    for path in candidates:
        if os.path.exists(path[0] if isinstance(path, tuple) else path):
            return path
    raise SystemExit("書体が見つからない: " + " / ".join(map(str, candidates)))

SANS = pick(SANS_CANDIDATES)

def sans(size, bold=False):
    """太字は Bold(700)。単語カードを焼く本番の書体が持つ、いちばん太い字に合わせる。"""
    font = ImageFont.truetype(SANS[1] if bold else SANS[0], int(round(size * S)))
    try:
        font.set_variation_by_name("Bold" if bold else "Regular")
    except OSError:
        pass                                     # 可変フォントでなければ、ファイルが太さを決める
    return font

# KanaRing.path("ナガイコトバノデータベース") の出力(viewBox 200)
RING = [(132.67, 175.21), (151.75, 36.39), (111.17, 18.76), (177.27, 72.54), (142.61, 170.06),
        (77.88, 178.96), (88.83, 181.24), (151.75, 163.61), (172.81, 137.73), (48.25, 163.61),
        (181.81, 105.60)]
RING_CENTER, RING_RADIUS = 100.0, 82.0

img = Image.new("RGB", (W * S, H * S), BG)
draw = ImageDraw.Draw(img)

def px(value):
    return int(round(value * S))

def tracked(x, baseline, text, font, color, tracking):
    """字間(letter-spacing)を足しながら 1 文字ずつ描く。"""
    cursor = x * S
    for char in text:
        draw.text((cursor, baseline * S), char, font=font, fill=color, anchor="ls")
        cursor += font.getlength(char) + tracking * S

# ── 背景: 長い言葉の壁 ───────────────────────────────────────────────────
# 語と並べ方は config/share_card_wall.json。並べ方の規則(JSON の note)は ShareCardWall#items と同じ。
CONFIG = os.path.join(os.path.dirname(__file__), "..", "config", "share_card_wall.json")
with open(CONFIG, encoding="utf-8") as f:
    WALL = json.load(f)

def hex_color(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))

def paint_wall():
    font = sans(WALL["font_size"], bold=True)
    words, fill = WALL["words"], hex_color(WALL["fill"])
    index = 0
    for row in range(WALL["rows"]):
        baseline = WALL["first_baseline"] + row * WALL["pitch"]
        x = WALL["indents"][row]
        while x < W:
            text = words[index % len(words)]
            tracked(x, baseline, text, font, fill, 0)
            x += sum(font.getlength(c) for c in text) / S + WALL["gap"]
            index += 1

paint_wall()

# ── 構図 ────────────────────────────────────────────────────────────────
CX = W / 2.0
BORDER_WIDTH, RADIUS = 2, 12            # サイトの墨の 1px・角 8px を、縮小されても残るよう太らせた値
PAPER = (0xff, 0xff, 0xff)              # --surface(札の面)

def center(text, baseline, font, color, tracking):
    """CX を中心に 1 行を置く(字間を足した幅で測る)。"""
    width = sum(font.getlength(c) for c in text) / S + tracking * (len(text) - 1)
    tracked(CX - width / 2.0, baseline, text, font, color, tracking)

def card(x0, y0, x1, y1, fill=PAPER, radius=RADIUS):
    """墨の枠の札。枠は外側に向けて BORDER_WIDTH、角の丸めは外周の半径。"""
    draw.rounded_rectangle([px(x0), px(y0), px(x1) - 1, px(y1) - 1], radius=px(radius),
                           fill=fill, outline=TEXT, width=px(BORDER_WIDTH))

# 看板の札。中身(円環の上端〜検索バーの下端)の上下に同じ余白を取り、画像の縦の中央に置く。
CARD_X0, CARD_X1, CARD_Y0, CARD_Y1 = 150, 1050, 131, 498
card(CARD_X0, CARD_Y0, CARD_X1, CARD_Y1)

# ── 印: サイト名の読みの円環(ホーム最上部の印と同じ図。外周の英字は小さすぎて読めないので置かない)──
# 色と太さの比は印(.ring-art--mark)に合わせる: 線と始点は墨、円は図の灰。
RING_PX = 80
LINE_WIDTH, CIRCLE_WIDTH = 1.6, 1.0
scale = RING_PX / 200.0
cx, cy = CX, 200.0

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

# ── サイト名 → 説明 ─────────────────────────────────────────────────────
TITLE = "長い言葉のデータベース"
LEAD  = "日本語の長い言葉を、読み・文字・韻・ジャンルから眺める"
TITLE_SIZE, LEAD_SIZE = 68, 28
TITLE_Y, LEAD_Y = 318, 368
center(TITLE, TITLE_Y, sans(TITLE_SIZE, bold=True), TEXT, TITLE_SIZE * TITLE_TRACKING)
center(LEAD, LEAD_Y, sans(LEAD_SIZE), TEXT_MUTED, LEAD_SIZE * LEAD_TRACKING)

# ── 検索バーの札(サイトのホームの検索バーと同じ作り。文言は layouts.search_placeholder / search_submit)──
BAR_WIDTH, BAR_Y0, BAR_Y1 = 660, 400, 462
bar_x0, bar_x1 = CX - BAR_WIDTH / 2.0, CX + BAR_WIDTH / 2.0
bar_mid = (BAR_Y0 + BAR_Y1) / 2.0
card(bar_x0, BAR_Y0, bar_x1, BAR_Y1)
draw.text((px(bar_x0 + 28), px(bar_mid)), "単語を検索", font=sans(26), fill=TEXT_SUBTLE, anchor="lm")
BUTTON_WIDTH, BUTTON_INSET = 124, 8
button_x0, button_x1 = bar_x1 - BUTTON_INSET - BUTTON_WIDTH, bar_x1 - BUTTON_INSET
draw.rounded_rectangle([px(button_x0), px(BAR_Y0 + BUTTON_INSET), px(button_x1), px(BAR_Y1 - BUTTON_INSET)],
                       radius=px(RADIUS - 4), fill=TEXT)
draw.text((px((button_x0 + button_x1) / 2.0), px(bar_mid)), "検索", font=sans(22, bold=True), fill=BG, anchor="mm")

OUT = os.path.join(os.path.dirname(__file__), "..", "public", "og-default.png")
img.resize((W, H), Image.LANCZOS).save(os.path.normpath(OUT))
