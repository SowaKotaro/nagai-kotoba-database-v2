# 公開の収録リクエスト・フォームにある「重複チェック」ボタンの判定(Issue 75)。
#
# 送信とは独立した任意操作で、結果がどうであれ送信は妨げない。判定は管理側の一括登録
# (step3)と同じ Levenshtein・同じしきい値で行い、読みが入力されていれば読みに、
# 無ければ表層形に当てる。
#
# 公開側から不特定多数に叩かれるため、既存語の一覧は Rails.cache に載せて DB の総なめが
# 毎回起きないようにする(Issue 52 で指摘済みの負荷が公開面へ露出するのを避ける)。
# 距離計算そのものは Levenshtein.far_apart? の枝刈りで、長さの近い語だけに絞られる。
class WordRequestDuplicateCheck
  CACHE_TTL = 1.hour
  # 1回の押下で照合する語数の上限(フォームの行数上限と同じ)。
  MAX_QUERIES = WordRequest::MAX_ITEMS
  # 1語あたりに見せる一致件数の上限(画面が流れないように絞る)。
  MAX_MATCHES = 5

  # 判定結果1語分。kind は :exact(完全一致) / :similar(似ている) / :none(該当なし)。
  Result = Struct.new(:surface, :reading, :kind, :matches, keyword_init: true) do
    def exact? = kind == :exact
    def similar? = kind == :similar
    def none? = kind == :none
  end

  # 一致した既存語(表示用)。word_id は詳細ページへのリンクに使う。
  Match = Struct.new(:word_id, :surface, :reading, :similarity, keyword_init: true)

  # 照合する1語。*_key は比較用に畳んだ値(照合順序 as_ci と同じ扱いに揃える)。
  Query = Struct.new(:surface, :reading, :surface_key, :reading_key, keyword_init: true)

  # queries: [{ surface:, reading: }, ...]。表層形が空の行は捨てる。
  def initialize(queries)
    @queries = Array(queries).filter_map { |query| build_query(query) }.first(MAX_QUERIES)
  end

  attr_reader :queries

  def any? = @queries.any?

  def call
    @queries.map { |query| judge(query) }
  end

  # 公開語の一覧 [word_id, 表層形, 読み, 表層形キー, 読みキー]。
  # 比較用のキーもキャッシュに含め、判定のたびに畳み直さないようにする。
  def self.corpus
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      WordSense.published.pluck("words.id", "words.surface", "word_senses.reading").map do |id, surface, reading|
        [ id, surface, reading, fold(surface), fold(reading) ]
      end
    end
  end

  # 収録語数と最終更新時刻をキーにする。語義の更新は touch: true で words.updated_at を
  # 動かすため、語の追加・注釈・語義の編集はすべてキーに反映される(llms-full.txt と同作法)。
  def self.cache_key
    scope = Word.annotated
    "word_request_duplicate_check/#{scope.count}-#{scope.maximum(:updated_at)&.to_i}"
  end

  # NFKC 正規化(半角カナ・合成濁点を畳む)し、ひらがなをカタカナへ寄せる。
  # DB 側の照合順序(utf8mb4_0900_as_ci)と同じく、かなの種類は同一視し清濁は区別する。
  def self.fold(value)
    value.to_s.unicode_normalize(:nfkc).tr("ぁ-ゖ", "ァ-ヶ")
  end

  private

  def build_query(query)
    surface = query[:surface].to_s.strip
    return nil if surface.blank?

    reading = query[:reading].to_s.strip
    Query.new(surface: surface, reading: reading,
              surface_key: self.class.fold(surface), reading_key: self.class.fold(reading))
  end

  def judge(query)
    exact = exact_matches(query)
    return result_for(query, :exact, exact) if exact.any?

    similar = similar_matches(query)
    return result_for(query, :similar, similar) if similar.any?

    result_for(query, :none, [])
  end

  def result_for(query, kind, matches)
    Result.new(surface: query.surface, reading: query.reading, kind: kind, matches: matches)
  end

  # 表層形がそのまま一致するか、読みが入力されていて読みが一致する語。
  def exact_matches(query)
    matches = corpus.filter_map do |word_id, surface, reading, surface_key, reading_key|
      hit = surface_key == query.surface_key ||
            (query.reading_key.present? && reading_key == query.reading_key)
      Match.new(word_id: word_id, surface: surface, reading: reading, similarity: 1.0) if hit
    end
    dedupe(matches)
  end

  # 読みが入力されていれば読み同士、無ければ表層形同士で類似度を測る。
  #
  # 照合のたびに String#chars を呼ぶとそれ自体が支配的なコストになるため、
  # クエリ側もコーパス側も分割済みの配列を使う(コーパスは1回の判定で使い回す)。
  def similar_matches(query)
    by_reading = query.reading_key.present?
    value_chars = (by_reading ? query.reading_key : query.surface_key).chars

    matches = split_corpus.filter_map do |word_id, surface, reading, surface_chars, reading_chars|
      target_chars = by_reading ? reading_chars : surface_chars
      next if target_chars.empty?

      similarity = Levenshtein.similarity_at_least_chars(value_chars, target_chars)
      next unless similarity

      Match.new(word_id: word_id, surface: surface, reading: reading, similarity: similarity)
    end
    dedupe(matches)
  end

  # 比較用キーを分割した [word_id, 表層形, 読み, 表層形の文字配列, 読みの文字配列]。
  # 1回の #call(最大10語)で使い回すため、語数×クエリ数ぶんの分割をしない。
  def split_corpus
    @split_corpus ||= corpus.map do |word_id, surface, reading, surface_key, reading_key|
      [ word_id, surface, reading, surface_key.chars, reading_key.chars ]
    end
  end

  # 同じ語に複数の語義がぶら下がると同じ word_id が並ぶため、語単位に畳んでから上位を採る。
  def dedupe(matches)
    matches.sort_by { |match| -match.similarity }.uniq(&:word_id).first(MAX_MATCHES)
  end

  def corpus = self.class.corpus
end
