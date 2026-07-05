# 単語の公開閲覧(一覧・詳細)。誰でも閲覧できる。書き込みは Admin::WordsController 側。
class WordsController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  PER_PAGE = 50

  # 一覧のファセット絞り込み。詳細/一覧の各データから単一条件で単語一覧に絞り込む入口。
  FACET_KEYS = %i[
    genre_id part_of_speech_id entity_type_id linguistic_feature_id word_origin_id
    reading_length mora_count first_char last_char
  ].freeze

  def index
    @page = [ params[:page].to_i, 1 ].max
    scope = filtered_words
    @active_facet = active_facet_label

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
  end

  private

  # ファセット指定があれば、その条件を満たす語義を持つ注釈済みの語だけに絞る。
  # 絞り込みロジックは詳細検索(WordSenseSearch)を再利用する。
  def filtered_words
    scope = Word.annotated
    return scope unless facet_active?

    sense_ids = WordSenseSearch.new(facet_params).results.reorder(nil).select(:word_id)
    scope.where(id: sense_ids)
  end

  def facet_params
    params.permit(*FACET_KEYS)
  end

  def facet_active?
    FACET_KEYS.any? { |key| params[key].present? }
  end

  # 現在の絞り込み条件を [ラベル, 値] で返す(表示用)。無ければ nil。
  def active_facet_label
    if (name = facet_name(Genre, :genre_id))
      [ WordSense.human_attribute_name(:genre), name ]
    elsif (name = facet_name(PartOfSpeech, :part_of_speech_id))
      [ WordSense.human_attribute_name(:part_of_speech), name ]
    elsif (name = facet_name(EntityType, :entity_type_id))
      [ WordSense.human_attribute_name(:entity_type), name ]
    elsif (name = facet_name(LinguisticFeature, :linguistic_feature_id))
      [ t("searches.linguistic_feature"), name ]
    elsif (name = facet_name(WordOrigin, :word_origin_id))
      [ t("words.show.origins"), name ]
    elsif params[:reading_length].present?
      [ t("words.show.reading_length"), t("words.show.chars", count: params[:reading_length]) ]
    elsif params[:mora_count].present?
      [ t("words.show.mora_count"), t("words.show.mora", count: params[:mora_count]) ]
    elsif params[:first_char].present?
      [ t("words.show.first_char"), params[:first_char] ]
    elsif params[:last_char].present?
      [ t("words.show.last_char"), params[:last_char] ]
    end
  end

  # マスタ(ジャンル・品詞など)を id で引いて名前を返す。無ければ nil。
  def facet_name(model, key)
    id = params[key].presence
    id && model.find_by(id: id)&.name
  end
end
