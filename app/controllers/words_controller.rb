# 単語の公開閲覧(一覧・詳細)。誰でも閲覧できる。書き込みは Admin::WordsController 側。
class WordsController < ApplicationController
  allow_unauthenticated_access only: %i[index show random]

  PER_PAGE = 100
  FEED_LIMIT = 20

  # 一覧の絞り込み。詳細検索(searches#index)からのリダイレクトと、
  # 詳細/一覧の各データからの単一条件ファセットリンクの両方を受ける。
  # HTML/JSON は絞り込み+ページネーション、Atom(Issue 28)は絞り込みに依らず新着を返す。
  def index
    @page = [ params[:page].to_i, 1 ].max
    @search = WordSenseSearch.new(search_filter_params)
    @sort = WordSort.new(params[:sort])
    # 不正な正規表現(URL 直打ち等)は条件から外して検索されるので、外したことを伝える。
    flash.now[:alert] = t("searches.regexp_error.#{@search.regexp_error}") if @search.regexp_error

    respond_to do |format|
      format.html { load_paginated_words }
      format.json { load_paginated_words }
      format.atom do
        @words = feed_words
        records = feed_cache_records
        fresh_when(etag: records, last_modified: records.map(&:updated_at).max, public: true)
      end
    end
  end

  def show
    # 未注釈の語は公開しない(RecordNotFound → 404)。
    # ジャンルはパンくず(大→中→小)を出すため祖先まで preload する。
    @word = Word.annotated.includes(
      word_senses: [
        { genre: { parent: :parent } }, :entity_type, :part_of_speech, :word_origins, :word_sense_variants,
        { word_sense_features: :linguistic_feature }
      ]
    ).find(params[:id])

    # 条件付きGET(ETag/Last-Modified)。更新が無ければ 304 を返し、関連語の
    # 組み立てもスキップする(Issue 26)。word_senses は touch: true で Word に伝わるが、
    # ジャンル等のマスタは touch しないので、名称変更を拾えるよう明示的に含める。
    records = @word.cache_dependencies
    return unless stale?(etag: records, last_modified: records.map(&:updated_at).max, public: true)

    # 単語間の内部リンク(関連語)。同ジャンル/同文字数/同先頭文字を各数件(Issue 23)。
    # JSON(Issue 25)では不要なのでそれ以外(HTML)のときだけ組み立てる。
    # format.html? での判定は Accept: */*(curl・クローラ)が false になり、
    # HTML テンプレートだけ描画されて 500 になるため使わない。
    @related_word_groups = RelatedWords.new(@word).groups unless request.format.json?
  end

  # 「ランダムに1語」導線。公開(注釈済み)から等確率で1語選び、その詳細へ 302 で飛ばす。
  # 語が無ければ一覧へフォールバックする。件数規模(〜1万)では RAND() ソートで十分。
  def random
    word = Word.annotated.order(Arel.sql("RAND()")).first
    redirect_to(word ? word_path(word) : words_path)
  end

  private

  # 絞り込み+ページネーションした一覧(HTML/JSON 用)。
  def load_paginated_words
    scope = filtered_words
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @words = scope.includes(word_senses: [ :entity_type, :part_of_speech ])
                  .order(@sort.order_clause)
                  .limit(PER_PAGE)
                  .offset((@page - 1) * PER_PAGE)
                  .to_a
  rescue ActiveRecord::StatementInvalid
    # MySQL が正規表現の照合を打ち切ったとき(regexp_time_limit 超過)だけ、
    # 500 にせず空の結果 + 警告で返す。正規表現を指定していないなら別の障害なので投げ直す。
    raise unless @search.search_regexp.present?

    flash.now[:alert] = t("searches.regexp_error.runtime")
    @words = []
    @total_count = 0
    @total_pages = 1
  end

  # 新着フィード(Atom 用)。注釈された順に新しいものから FEED_LIMIT 件。
  # リード文がジャンルのパンくず(大→中→小)を使うため、words#show と同じ深さで祖先まで
  # preload する(genre 止まりだと語ごとに parent を遅延ロードする N+1 になる。Issue 54)。
  def feed_words
    Word.annotated
        .includes(word_senses: { genre: { parent: :parent } })
        .order(annotated_at: :desc, id: :desc)
        .limit(FEED_LIMIT)
        .to_a
  end

  # フィードの鮮度判定(条件付きGET)に関わるレコード一式。エントリ本文のリード文は
  # ジャンル階層の名称を含むが、マスタは touch されず Word が古いままになるため、
  # ジャンル(祖先含む)も明示的に加える(words#show の cache_dependencies と同じ理由)。
  def feed_cache_records
    @words.flat_map do |word|
      genres = word.word_senses.flat_map { |sense| sense.genre&.self_and_ancestors }
      [ word, *genres.compact ]
    end
  end

  # 条件指定があれば、その条件を満たす語義を持つ注釈済みの語だけに絞る。
  # 絞り込みロジックは詳細検索(WordSenseSearch)を再利用する。
  def filtered_words
    scope = Word.annotated
    return scope unless @search.conditions?

    scope.where(id: @search.results.reorder(nil).select(:word_id))
  end

  # 検索フォーム経由は配列、ファセットリンクは単一値で届くキーがあるため両方許可する。
  def search_filter_params
    params.permit(
      :q, :regexp, :reading_length_min, :reading_length_max, :reading_length, :mora_count,
      :char_type_pattern, :char_type_partial, :char_type_ignore_case,
      :rhythm_pattern, :vowel_reading, :word_origin_id,
      :genre_id, :first_char, :last_char,
      :part_of_speech_id, :entity_type_id, :linguistic_feature_id,
      genre_id: [], first_char: [], last_char: [], word_origin_id: [],
      part_of_speech_id: [], entity_type_id: [], linguistic_feature_id: []
    )
  end
end
