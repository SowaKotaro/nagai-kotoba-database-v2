# 語義の公開検索・絞り込み(Issue 9)。誰でも利用できる。
class SearchesController < ApplicationController
  allow_unauthenticated_access only: :index

  PER_PAGE = 50

  def index
    @search = WordSenseSearch.new(search_params)
    scope = @search.results

    @page = [ params[:page].to_i, 1 ].max
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @word_senses = scope.preload(:word, :genre, :entity_type, :part_of_speech)
                        .limit(PER_PAGE)
                        .offset((@page - 1) * PER_PAGE)
  end

  private

  def search_params
    params.permit(
      :reading_length_min, :reading_length_max, :first_char, :last_char,
      :char_type_pattern, :rhythm_pattern,
      :genre_id, :part_of_speech_id, :entity_type_id, :linguistic_feature_id
    )
  end
end
