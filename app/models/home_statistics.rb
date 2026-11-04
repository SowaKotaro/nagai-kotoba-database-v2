# ホームが今日の一語を選ぶときの収録語数(看板には数を出さない。docs/design.md §5.2)。
#
# 毎リクエスト COUNT を打たないよう 1 時間キャッシュする(Issue 26)。今日の一語(Word.featured_on)は
# ここでキャッシュした語数で選ぶ(公開・保留の直後に実際の語数とずれても数え直さない)。
#
# 同じ収録語数でも、About(AboutStatistics)と /stats(SiteStatistics)は 1 日キャッシュする(docs/data-model.md §8)。
# 揃えるかはオーナー判断で、ここでは変えない。
# race_condition_ttl は持たない(COUNT だけで軽い。足すと作り直しの最中の振る舞いが変わる)。
# 種別: クエリ・集計（読み取りとキャッシュ）。
class HomeStatistics
  # 集計の形を変えたら、キャッシュに残る旧い値を踏まないよう版を上げる。
  CACHE_KEY = "home_statistics/v2".freeze
  CACHE_TTL = 1.hour

  def self.word_count
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { Word.annotated.count }
  end
end
