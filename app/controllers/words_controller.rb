# 単語の公開閲覧(一覧・詳細)。誰でも閲覧できる。書き込みは Admin::WordsController 側。
class WordsController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  PER_PAGE = 50
  FEED_LIMIT = 20

  # 一覧の絞り込み。詳細検索(searches#index)からのリダイレクトと、
  # 詳細/一覧の各データからの単一条件ファセットリンクの両方を受ける。
  # HTML/JSON は絞り込み+ページネーション、Atom(Issue 28)は絞り込みに依らず新着を返す。
  def index
    @page = [ params[:page].to_i, 1 ].max
    @search = WordSenseSearch.new(search_filter_params)
    @sort = WordSort.new(params[:sort])

    respond_to do |format|
      format.html { load_paginated_words }
      format.json { load_paginated_words }
      format.atom { @words = feed_words }
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
  end

  # 新着フィード(Atom 用)。注釈された順に新しいものから FEED_LIMIT 件。
  def feed_words
    Word.annotated
        .includes(word_senses: :genre)
        .order(annotated_at: :desc, id: :desc)
        .limit(FEED_LIMIT)
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
      :q, :reading_length_min, :reading_length_max, :reading_length, :mora_count,
      :char_type_pattern, :char_type_partial, :char_type_ignore_case,
      :rhythm_pattern, :vowel_reading, :word_origin_id,
      :genre_id, :first_char, :last_char,
      :part_of_speech_id, :entity_type_id, :linguistic_feature_id,
      genre_id: [], first_char: [], last_char: [], word_origin_id: [],
      part_of_speech_id: [], entity_type_id: [], linguistic_feature_id: []
    )
  end
end
