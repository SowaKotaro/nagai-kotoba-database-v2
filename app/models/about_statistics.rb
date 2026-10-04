# About の標識と本文に出す収録語数。毎リクエスト COUNT を打つほどの値ではないので 1 日置く。
# ホームの収録語数(HomeStatistics)とはキャッシュの長さが違う(1 時間。揃えるかはオーナー判断)。
# race_condition_ttl は持たない(COUNT 1 本で軽い。足すと作り直しの最中の振る舞いが変わる)。
# 種別: クエリ・集計（読み取りとキャッシュ）。
class AboutStatistics
  # 集計の形を変えたら、キャッシュに残る旧い値を踏まないよう版を上げる。
  CACHE_KEY = "about_statistics/v1".freeze
  CACHE_TTL = 1.day

  def self.word_count
    Rails.cache.fetch("#{CACHE_KEY}/word_count", expires_in: CACHE_TTL) { Word.annotated.count }
  end
end
