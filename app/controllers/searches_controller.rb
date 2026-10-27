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
  # 並びは seeds の投入順(= id 順)に揃える。言語学的特徴だけは、管理画面と同じく用語解説の順にする。
  def load_filter_masters
    @genres_by_parent = Genre.order(:id).group_by(&:parent_id)
    @parts_of_speech = PartOfSpeech.order(:id)
    @entity_types = EntityType.order(:id)
    @word_origins = WordOrigin.order(:id)
    @linguistic_features = LinguisticFeature.in_glossary_order
    load_published_counts
  end

  # 選択肢に添える公開語義数。索引(/browse・/genres)と同じ集計(PublishedSenseCounts。1時間キャッシュ)を使う。
  # 50音表は件数の濃淡(ヒート)で塗るので、表ごとの最大値も渡す(0除算を避けるため 0 で埋める)。
  def load_published_counts
    @genre_counts = PublishedSenseCounts.by_genre
    @first_char_counts = PublishedSenseCounts.by_first_char
    @first_char_max = @first_char_counts.values.max || 0
    @last_char_counts = PublishedSenseCounts.by_last_char
    @last_char_max = @last_char_counts.values.max || 0
    @reading_length_histogram = reading_length_histogram(PublishedSenseCounts.by_reading_length)
    @reading_length_histogram_max = @reading_length_histogram.values.max || 0
  end

  # 読みの文字数のスライダーに敷く度数分布 { 10 => 391, ..., 30 => 4 }。目盛りはスライダーと同じ
  # (下端は収録基準、上端は SearchesHelper::READING_LENGTH_SLIDER_MAX)。上端は「以上」の意味なので、
  # 上端の棒には上端より長い語義もまとめて数える。
  def reading_length_histogram(counts)
    lowest, highest = WordSense::MIN_READING_LENGTH, SearchesHelper::READING_LENGTH_SLIDER_MAX
    (lowest..highest).index_with do |length|
      length == highest ? counts.sum { |key, count| key.to_i >= highest ? count : 0 } : counts[length].to_i
    end
  end

  # 受け付ける条件の正は WordSenseSearch::PERMITTED_PARAMS(単語一覧と同じ集合。一覧の「条件を変える」は
  # 一覧のクエリをそのまま渡すので、同じ集合でないと条件が黙って落ちる)。
  def search_params
    params.permit(*WordSenseSearch::PERMITTED_PARAMS)
  end
end
