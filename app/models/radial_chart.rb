# 円周に等間隔で項目を並べ、値の大小を「中心からの距離」で表す放射図の座標を出す値オブジェクト。
#
# 五十音円環(KanaRing)とまったく同じ viewBox・中心・外周半径の上に描くので、
# サイト内の線画は「円」ひとつの家族に収まる(docs/design.md §5.9)。
# 円環が「1語の読み」を線にするのに対し、こちらは「並んだ数値」を線にする。
#
# 座標は 200x200 の viewBox 前提。
# 種別: 値オブジェクト（DB に触れない）。
class RadialChart
  VIEWBOX = KanaRing::VIEWBOX
  CENTER = KanaRing::CENTER
  RADIUS = KanaRing::RADIUS

  # 最小値でも中心に潰れないよう、半径の 20% を下限にする。
  # 最大値で割る正規化だと差が読めなくなるため、最小値〜最大値を 20〜100% に写す
  # (docs/design.md §5.9。2026-09-03 の実測で決めた規則)。ジャンル一覧の横棒(percent)も同じ写像。
  MIN_PERCENT = 20
  MIN_RATIO = MIN_PERCENT / 100.0

  # 図の 1 点(項目名・元の値・頂点の座標・その項目が立つ外周上の座標)。
  # 外周の座標は「目盛りの放射線」を引くために持つ。
  Point = Data.define(:label, :value, :cx, :cy, :outer_cx, :outer_cy)

  # 値を、最小値〜最大値を MIN_PERCENT〜100 に写した整数の百分率にする(ジャンル一覧の横棒の幅)。
  # 比率を求めてから 100 倍すると浮動小数点の誤差で丸めが 1 ずれる値があるので、百分率のまま計算する。
  # points と違い項目数を問わない(points は 3 項目未満で空を返す)。
  def self.percent(value, min, max)
    return 100 if max == min

    (MIN_PERCENT + (value - min) * (100 - MIN_PERCENT).to_f / (max - min)).round
  end

  # [[ラベル, 値], ...] を受け取り、頂点を頂上(-90度)から時計回りに等間隔で並べて返す。
  # 項目が 3 つ未満だと面にならないので空を返す(呼び出し側で図ごと出さない)。
  def self.points(entries)
    entries = entries.to_a
    return [] if entries.size < 3

    values = entries.map { |_, value| value.to_f }
    min, max = values.minmax
    span = max - min

    entries.each_with_index.map do |(label, value), index|
      ratio = span.zero? ? 1.0 : MIN_RATIO + (value.to_f - min) / span * (1 - MIN_RATIO)
      angle = (-90 + index * 360.0 / entries.size) * Math::PI / 180
      distance = RADIUS * ratio
      Point.new(
        label: label,
        value: value,
        cx: (CENTER + distance * Math.cos(angle)).round(2),
        cy: (CENTER + distance * Math.sin(angle)).round(2),
        outer_cx: (CENTER + RADIUS * Math.cos(angle)).round(2),
        outer_cy: (CENTER + RADIUS * Math.sin(angle)).round(2)
      )
    end
  end
end
