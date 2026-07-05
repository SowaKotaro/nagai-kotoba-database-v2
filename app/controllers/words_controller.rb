# 単語の公開閲覧(一覧・詳細)。誰でも閲覧できる。書き込みは Admin::WordsController 側。
class WordsController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  PER_PAGE = 50

  def index
    @page = [ params[:page].to_i, 1 ].max
    @total_count = Word.annotated.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @words = Word.annotated
                 .includes(word_senses: [ :entity_type, :part_of_speech ])
                 .order(:surface)
                 .limit(PER_PAGE)
                 .offset((@page - 1) * PER_PAGE)
  end

  def show
    # 未注釈の語は公開しない(RecordNotFound → 404)。
    @word = Word.annotated.includes(
      word_senses: [ :genre, :entity_type, :part_of_speech, { word_sense_features: :linguistic_feature } ]
    ).find(params[:id])
  end
end
