# インデックスを許可している単一条件の一覧(ファセット面。/words?genre_id=3 など)を、公開語義の件数つきで列挙する。
# ファセット面のサイトマップ(SitemapsController#facets)が使う。
#
# 面の種類は WordSenseSearch::INDEXABLE_FACET_KEYS、値はマスタの行・50音表の字・実在する文字数とモーラ数だけなので、
# 列挙は有限に収まる(条件の組み合わせ・並び替え・ページ送りは面ではない。docs/seo-plan.md §5 C-2)。
# 件数は索引のページと同じ PublishedSenseCounts のキャッシュから引くので、ここで公開語義を数え直さない。
# 種別: クエリ・集計（読み取りとキャッシュ）。
class IndexableFacets
  # key と value は /words の絞り込みのパラメータと値、count はその面の公開語義数。
  Facet = Struct.new(:key, :value, :count)

  # サイトマップに載せる面の、公開語義数の下限。語義が 1〜2 件の面は、その語の単語詳細と中身がほぼ重なるので、
  # 「登録してほしい面」としては伝えない。インデックスの可否は変えない(1 件以上なら index のまま。
  # app/views/words/index.html.erb の indexable)。語が増えて下限に届いた面は、次の作り直しで載る。
  SITEMAP_MIN_COUNT = 3

  # 面の種類ごとの、件数の出どころ(PublishedSenseCounts のメソッド)。ジャンルだけは上位の分類へ合算するので別に組む。
  COUNT_SOURCES = {
    part_of_speech_id: :by_part_of_speech, entity_type_id: :by_entity_type, word_origin_id: :by_word_origin,
    first_char: :by_first_char, last_char: :by_last_char,
    reading_length: :by_reading_length, mora_count: :by_mora_count, linguistic_feature_id: :by_linguistic_feature
  }.freeze

  # 値がかな 1 文字の面(先頭文字・末尾文字)。
  KANA_FACET_KEYS = %i[first_char last_char].freeze

  # 文字の面に出す字。索引(/browse)の 50音表と同じ字に限る。照合順序 as_ci は小書き・ひらがなを
  # 同一視するので(docs/data-model.md §6)、集計のキーに現れた字をそのまま面にすると、同じ中身の面が別の字で立ちうる。
  KANA = KanaRow::TABLE_COLUMNS.flatten.compact.freeze

  class << self
    # インデックスを許可している面のうち、公開語義が 1 件以上あるもの(面の種類の順、その中は値の順)。
    def all
      WordSenseSearch::INDEXABLE_FACET_KEYS.flat_map do |key|
        counts_for(key).filter_map { |value, count| Facet.new(key, value, count) if count.positive? }.sort_by(&:value)
      end
    end

    # サイトマップに載せる面。
    def for_sitemap = all.select { |facet| facet.count >= SITEMAP_MIN_COUNT }

    private

    # { 値 => 公開語義数 }。未設定(nil)にまとまった件数は面にならないので落とす。
    def counts_for(key)
      return genre_counts if key == :genre_id

      counts = PublishedSenseCounts.public_send(COUNT_SOURCES.fetch(key)).except(nil)
      KANA_FACET_KEYS.include?(key) ? counts.slice(*KANA) : counts
    end

    # ジャンルは大・中・小のどれでも面になる(/genres がそれぞれへリンクする)。語義に付くのは小分類なので、
    # その件数を自身と上位の分類のそれぞれに足す(GenresHelper#genre_published_count と同じ数になる)。
    def genre_counts
      parent_ids = Genre.pluck(:id, :parent_id).to_h
      PublishedSenseCounts.by_genre.each_with_object(Hash.new(0)) do |(genre_id, count), totals|
        while parent_ids.key?(genre_id)
          totals[genre_id] += count
          genre_id = parent_ids[genre_id]
        end
      end
    end
  end
end
