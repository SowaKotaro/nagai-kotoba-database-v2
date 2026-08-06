# 公開(注釈済み)語義の件数集計。50音索引(/browse)とジャンルのハブ(/genres)が使う。
#
# どれも「公開語義の全件を GROUP BY して数える」ので、語数に正比例して重くなる
# (1万語規模で 30〜70ms/本)。中身は導線に添える件数でしかなく、少し古くても表示に
# 支障が無いため短時間キャッシュする。統計ページ(SiteStatistics)と同じ考え方だが、
# あちらが日次の読み物なのに対しこちらは索引なので、TTL は1時間と短くする。
class PublishedSenseCounts
  CACHE_TTL = 1.hour
  # 期限切れ直後に複数リクエストが重なっても、集計し直すのは1本だけにする。
  RACE_CONDITION_TTL = 30.seconds
  # 集計の形を変えたらキャッシュに残る旧オブジェクトを踏まないようバージョンを上げる。
  CACHE_KEY = "published_sense_counts/v1".freeze

  class << self
    # 読みの先頭文字ごとの語義数 { "ア" => 12, ... }。
    def by_first_char = fetch(:first_char) { WordSense.published.group(:first_char).count }

    # 読みの文字数ごとの語義数 { 12 => 34, ... }。
    def by_reading_length = fetch(:reading_length) { WordSense.published.group(:reading_length).count }

    # 小分類ジャンルごとの語義数 { genre_id => 5, ... }。上位は子の合計で導出する。
    def by_genre = fetch(:genre) { WordSense.published.group(:genre_id).count }

    private

    def fetch(name, &)
      Rails.cache.fetch("#{CACHE_KEY}/#{name}", expires_in: CACHE_TTL,
                                                race_condition_ttl: RACE_CONDITION_TTL, &)
    end
  end
end
