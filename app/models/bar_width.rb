# 並んだ数値の 1 つを、横棒の幅(整数の百分率)にする値オブジェクト。
# ジャンル一覧(/genres)と詳細検索のジャンル絞り込みの、大分類の横棒に使う。
#
# 最大値で割る正規化だと、語義数の近い大分類どうしの差が棒の長さに出ない。
# 最小値〜最大値を MIN_PERCENT〜100 に写して差を作る(docs/design.md §5.9。2026-09-03 の実測で決めた規則)。
# 種別: 値オブジェクト（DB に触れない）。
class BarWidth
  # 最小値の棒でも消えないよう、幅の 20% を下限にする。
  MIN_PERCENT = 20

  # 比率を求めてから 100 倍すると浮動小数点の誤差で丸めが 1 ずれる値があるので、百分率のまま計算する。
  def self.call(value, min, max)
    return 100 if max == min

    (MIN_PERCENT + (value - min) * (100 - MIN_PERCENT).to_f / (max - min)).round
  end
end
