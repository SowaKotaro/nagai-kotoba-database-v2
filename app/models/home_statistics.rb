# ホームの看板に出す数(収録語数・語義数・ジャンル数・今月の新収録)。
#
# 毎リクエスト COUNT を打たないよう 1 時間キャッシュする(Issue 26)。「今月の」を含むので、
# キーに年月を持たせて、月が変わった瞬間に作り直す。今日の一語(HomeController#featured_word)は
# ここでキャッシュした語数で選ぶ(公開・保留の直後に実際の語数とずれても数え直さない)。
#
# 同じ名前の数でも、画面ごとに定義とキャッシュの長さが違う。収録語数は About(AboutStatistics)と
# /stats(SiteStatistics)が 1 日、ジャンル数は /genres・/stats と数え方が違う(docs/data-model.md §8)。
# 揃えるかはオーナー判断で、ここでは変えない。
# race_condition_ttl は持たない(COUNT だけで軽い。足すと作り直しの最中の振る舞いが変わる)。
# 種別: クエリ・集計（読み取りとキャッシュ）。
class HomeStatistics
  # 集計の形を変えたら、キャッシュに残る旧い値を踏まないよう版を上げる。
  CACHE_KEY = "home_statistics/v1".freeze
  CACHE_TTL = 1.hour

  # { words:, senses:, genres:, monthly_new: }
  def self.fetch
    Rails.cache.fetch("#{CACHE_KEY}/#{Date.current.strftime('%Y-%m')}", expires_in: CACHE_TTL) do
      {
        words: Word.annotated.count,
        senses: WordSense.published.count,
        # マスタの小分類の全件(公開語の有無を問わない。docs/data-model.md §8.1)。
        genres: Genre.small.count,
        # 更新が続いていることが一目で分かる指標。
        monthly_new: Word.annotated_this_month.count
      }
    end
  end
end
