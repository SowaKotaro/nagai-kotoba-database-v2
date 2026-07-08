# 語義の公開検索・絞り込み(Issue 9)。誰でも利用できる。
class SearchesController < ApplicationController
  allow_unauthenticated_access only: %i[index]

  # 詳細な検索フォーム(長さ・50音・ジャンル・品詞など全条件)。結果はこのページでは出さず、
  # 検索実行(フォーム送信 = commit あり)時は空条件を除いて単語一覧へリダイレクトする。
  # commit なし(条件変更リンクからの遷移など)は、受け取った条件をフォームに反映して表示するだけ。
  def index
    @search = WordSenseSearch.new(search_params)
    if params[:commit].present?
      redirect_to words_path(@search.to_query_params)
      return
    end

    load_filter_masters
  end

  private

  # フォームの選択肢(ドロップダウンをやめて一覧/階層で選ばせるため一括読み込み)。
  # 並びは seeds の投入順(= id 順)に揃える。
  def load_filter_masters
    @genres_by_parent = Genre.order(:id).group_by(&:parent_id)
    @parts_of_speech = PartOfSpeech.order(:id)
    @entity_types = EntityType.order(:id)
    @word_origins = WordOrigin.order(:id)
    @linguistic_features = LinguisticFeature.order(:id)
  end

  def search_params
    # genre_id / word_origin_id はフォームからは配列、ファセットリンクからは単一値で
    # 届くため両方許可する。vowel_reading は母音パターン検索用の生カナ入力。
    params.permit(
      :q, :reading_length_min, :reading_length_max,
      :char_type_pattern, :char_type_partial, :char_type_ignore_case,
      :rhythm_pattern, :vowel_reading, :genre_id, :word_origin_id,
      genre_id: [], first_char: [], last_char: [], word_origin_id: [],
      part_of_speech_id: [], entity_type_id: [], linguistic_feature_id: []
    )
  end
end
