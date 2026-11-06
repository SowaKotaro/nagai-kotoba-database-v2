# -*- coding: utf-8 -*-
"""public/icon.svg・public/favicon.ico・public/apple-touch-icon.png を描き直すための一回きりの道具。

   図は白い札(墨の枠)の上に、太字の「長」を 1 字、少し傾けて置いたもの(docs/design.md §5.1。2026-11-06 オーナー指示)。
   札は水平のままで、傾けるのは字だけ。札は白の面＋墨の枠で、サイトの札と同じ作り。
   白い札なのでタブがライトでもダークでも沈まず、以前のような prefers-color-scheme での入れ替えは要らない。
   角丸は持たない(16px まで縮むと潰れるだけ。2026-09-10)。
   色はトークン(tokens.css)のライトの値をリテラルで持つ。単体のファイルなので、トークンを変えても追従しない。
   SVG のコメントに「--」は書けない(XML として不正になる)ので、SVG の注記ではトークン名の接頭辞を付けない。

   実行: python3 script/favicon.py   (要 Pillow・fontTools。可変フォントの Noto Sans JP が要る)
   SVG は字を輪郭(path)にして焼くので、見る側の環境に字体は要らない。PNG / ICO は Pillow で 8 倍に描いて縮小する。
   SVG と PNG は同じ幾何(札の大きさ・枠・字の高さ・中心・傾き)から作る。"""
import io
import os
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from PIL import Image, ImageDraw, ImageFont

CHAR = "長"
WEIGHT = 800                          # サイトの強調の太さ(800)と同じ。可変フォントの wght 軸で選ぶ
TILT_DEG = 10                         # 字を反時計回りに傾ける角度(札は傾けない)
PLATE_RATIO = 0.86                    # 札の一辺(canvas に対する比。四隅に少し余白を残す)
PLATE_BORDER = 0.046                  # 枠の太さ(札の一辺に対する比。16px で約 0.6px)
GLYPH_HEIGHT = 0.72                   # 字の高さ(札の一辺に対する比。傾けても内側の白に収まる)

PAPER = (0xff, 0xff, 0xff)            # surface トークン
INK = (0x2f, 0x27, 0x25)              # text トークン
GROUND = (0xfa, 0xfa, 0xfa)           # bg トークン(apple-touch-icon の地。OS が透過を黒で埋めるので全面を塗る)

VIEW = 200                            # SVG の viewBox
SS = 8                                # 縮小前の倍率
ICO_SIZES = (16, 32, 48)
TOUCH_SIZE = 180
TOUCH_MARGIN = 0.86                   # apple-touch-icon は札を一回り小さくして、OS が角を丸めても欠けないようにする

FONT_CANDIDATES = [
    "/mnt/c/Windows/Fonts/NotoSansJP-VF.ttf",    # WSL から見た Windows の Noto Sans JP(wght 100〜900 の可変)
]
PUBLIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "public")


def font_path():
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return path
    raise SystemExit("可変フォントが見つからない: " + " / ".join(FONT_CANDIDATES))


def glyph_outline():
    """「長」だけを残した wght=WEIGHT の字体(fontTools)を返す。全グリフを具体化すると重いので先に削る。"""
    font = TTFont(font_path())
    options = Options()
    options.layout_features = []
    subsetter = Subsetter(options)
    subsetter.populate(text=CHAR)
    subsetter.subset(font)
    return instancer.instantiateVariableFont(font, {"wght": WEIGHT})


def svg():
    font = glyph_outline()
    glyphs = font.getGlyphSet()
    name = font.getBestCmap()[ord(CHAR)]
    bounds = BoundsPen(glyphs)
    glyphs[name].draw(bounds)
    x0, y0, x1, y1 = bounds.bounds

    side = VIEW * PLATE_RATIO
    origin = (VIEW - side) / 2
    border = side * PLATE_BORDER
    scale = side * GLYPH_HEIGHT / (y1 - y0)           # 字の高さを札に対する比にそろえる
    cx, cy = VIEW / 2, VIEW / 2
    # フォントは y が上向き。インク領域の中心を札の中心へ置き、y を反転する。
    matrix = (scale, 0, 0, -scale, cx - scale * (x0 + x1) / 2, cy + scale * (y0 + y1) / 2)
    pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
    glyphs[name].draw(TransformPen(pen, matrix))

    inner = side - 2 * border
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- ファビコン。水平の白い札(墨の枠)に、太字(800)の「長」を 1 字、反時計回りに {TILT_DEG}° 傾けて置いたもの。
     script/favicon.py が描く(字は輪郭に焼いてあるので字体は要らない)。
     単体ファイルなので色はトークンと同値をリテラルで持つ(札は surface トークンの #FFFFFF、墨は text トークンの #2F2725)。
     白い札は、タブがライトでもダークでも沈まないので、prefers-color-scheme での入れ替えは持たない。 -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {VIEW} {VIEW}">
  <rect x="{origin:.1f}" y="{origin:.1f}" width="{side:.1f}" height="{side:.1f}" fill="#2F2725"/>
  <rect x="{origin + border:.1f}" y="{origin + border:.1f}" width="{inner:.1f}" height="{inner:.1f}" fill="#FFFFFF"/>
  <path fill="#2F2725" transform="rotate({-TILT_DEG} {cx:g} {cy:g})" d="{pen.getCommands()}"/>
</svg>
"""


def glyph_mask(px, side):
    """px 四方に、インク領域の中心が中央・高さが side * GLYPH_HEIGHT の「長」を TILT_DEG 傾けて描いた 8bit マスク。"""
    path = font_path()
    size = 400
    probe = ImageFont.truetype(path, size)
    probe.set_variation_by_axes([WEIGHT])
    _, top, _, bottom = probe.getbbox(CHAR)
    font = ImageFont.truetype(path, int(size * side * GLYPH_HEIGHT / (bottom - top)))
    font.set_variation_by_axes([WEIGHT])
    left, top, right, bottom = font.getbbox(CHAR)
    mask = Image.new("L", (px, px), 0)
    ImageDraw.Draw(mask).text((px / 2 - (left + right) / 2, px / 2 - (top + bottom) / 2), CHAR, font=font, fill=255)
    return mask.rotate(TILT_DEG, resample=Image.BICUBIC, center=(px / 2, px / 2))


def raster(out, ground=None, margin=1.0):
    """out 四方の画像。ground が None なら札の外は透明、あれば全面をその色で塗る。"""
    px = out * SS
    side = px * PLATE_RATIO * margin
    origin = (px - side) / 2
    border = side * PLATE_BORDER
    image = Image.new("RGBA", (px, px), ground + (255,) if ground else (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rectangle([origin, origin, origin + side - 1, origin + side - 1], fill=INK + (255,))
    draw.rectangle([origin + border, origin + border, origin + side - 1 - border, origin + side - 1 - border],
                   fill=PAPER + (255,))
    image.paste(Image.new("RGBA", (px, px), INK + (255,)), (0, 0), glyph_mask(px, side))
    return image.resize((out, out), Image.LANCZOS)


def write(name, data):
    path = os.path.normpath(os.path.join(PUBLIC, name))
    with open(path, "wb") as f:
        f.write(data)
    print("wrote", path)


if __name__ == "__main__":
    write("icon.svg", svg().encode("utf-8"))

    frames = [raster(s) for s in ICO_SIZES]
    buffer = io.BytesIO()
    frames[-1].save(buffer, format="ICO", sizes=[(s, s) for s in ICO_SIZES], append_images=frames[:-1])
    write("favicon.ico", buffer.getvalue())

    # iOS は透過を黒で埋め、角を自分で丸める。全面を地で塗り、札は一回り小さくして角を食われないようにする。
    buffer = io.BytesIO()
    raster(TOUCH_SIZE, ground=GROUND, margin=TOUCH_MARGIN).convert("RGB").save(buffer, format="PNG", optimize=True)
    write("apple-touch-icon.png", buffer.getvalue())
