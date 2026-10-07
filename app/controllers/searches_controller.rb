# 語義の公開検索・絞り込み(Issue 9)。誰でも利用できる。
class SearchesController < ApplicationController
  allow_unauthenticated_access only: %i[index]

  # 詳細な検索フォーム(長さ・50音・ジャンル・品詞など全条件)。結果はこのページでは出さず、
  # 検索実行(フォーム送信 = commit あり)時は空条件を除いて単語一覧へリダイレクトする。
  # commit なし(条件変更リンクからの遷移など)は、受け取った条件をフォームに反映して表示するだけ。
  def index
    @search = WordSenseSearch.new(search_params)
    if params[:commit].present? && @search.regexp_error.nil?
      redirect_to words_path(@search.to_query_params)
      return
    end

    # 正規表現が不正なら一覧へ飛ばさず、フォームに入力を残したまま理由を伝える。
    flash.now[:alert] = t("searches.regexp_error.#{@search.regexp_error}") if @search.regexp_error
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

  # 受け付ける条件の正は WordSenseSearch::PERMITTED_PARAMS(単語一覧と同じ集合。一覧の「条件を変える」は
  # 一覧のクエリをそのまま渡すので、同じ集合でないと条件が黙って落ちる)。
  def search_params
    params.permit(*WordSenseSearch::PERMITTED_PARAMS)
  end
end
