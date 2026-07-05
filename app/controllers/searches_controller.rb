# 語義の公開検索・絞り込み(Issue 9)。誰でも利用できる。
class SearchesController < ApplicationController
  allow_unauthenticated_access only: %i[index simple]

  PER_PAGE = 50

  # 詳細な検索(長さ・50音・ジャンル・品詞など全条件)。結果は単語一覧で返す。
  def index
    @search = WordSenseSearch.new(search_params)
    scope = Word.annotated.where(id: @search.results.reorder(nil).select(:word_id))
    @page = [ params[:page].to_i, 1 ].max
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @words = scope.includes(word_senses: [ :part_of_speech, :entity_type ])
                  .order(:surface)
                  .limit(PER_PAGE)
                  .offset((@page - 1) * PER_PAGE)

    load_filter_masters
  end

  # 簡素な検索(キーワードのみ・表層形/読みの部分一致)。単語単位で一覧表示する。
  def simple
    @q = params[:q].to_s.strip
    @page = [ params[:page].to_i, 1 ].max
    scope = @q.present? ? Word.annotated.keyword(@q) : Word.none

    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @words = scope.includes(word_senses: [ :part_of_speech, :entity_type ])
                  .order(:surface)
                  .limit(PER_PAGE)
                  .offset((@page - 1) * PER_PAGE)
  end

  private

  # フォームの選択肢(ドロップダウンをやめて一覧/階層で選ばせるため一括読み込み)。
  def load_filter_masters
    @genres_by_parent = Genre.order(:name).group_by(&:parent_id)
    @parts_of_speech = PartOfSpeech.order(:name)
    @entity_types = EntityType.order(:name)
    @linguistic_features = LinguisticFeature.order(:name)
  end

  def search_params
    params.permit(
      :q, :reading_length_min, :reading_length_max,
      :char_type_pattern, :rhythm_pattern, :genre_id,
      first_char: [], last_char: [],
      part_of_speech_id: [], entity_type_id: [], linguistic_feature_id: []
    )
  end
end
