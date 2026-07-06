# 単語の公開閲覧(一覧・詳細)。誰でも閲覧できる。書き込みは Admin::WordsController 側。
class WordsController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  PER_PAGE = 50

  # 一覧の絞り込み。詳細検索(searches#index)からのリダイレクトと、
  # 詳細/一覧の各データからの単一条件ファセットリンクの両方を受ける。
  def index
    @page = [ params[:page].to_i, 1 ].max
    @search = WordSenseSearch.new(search_filter_params)
    scope = filtered_words

    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @words = scope.includes(word_senses: [ :entity_type, :part_of_speech ])
                  .order(:surface)
                  .limit(PER_PAGE)
                  .offset((@page - 1) * PER_PAGE)
  end

  def show
    # 未注釈の語は公開しない(RecordNotFound → 404)。
    @word = Word.annotated.includes(
      word_senses: [
        :genre, :entity_type, :part_of_speech, :word_origins, :word_sense_variants,
        { word_sense_features: :linguistic_feature }
      ]
    ).find(params[:id])
    # 単語間の内部リンク(関連語)。同ジャンル/同文字数/同先頭文字を各数件(Issue 23)。
    @related_word_groups = RelatedWords.new(@word).groups
  end

  private

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
      :char_type_pattern, :rhythm_pattern, :word_origin_id,
      :genre_id, :first_char, :last_char,
      :part_of_speech_id, :entity_type_id, :linguistic_feature_id,
      genre_id: [], first_char: [], last_char: [],
      part_of_speech_id: [], entity_type_id: [], linguistic_feature_id: []
    )
  end
end
