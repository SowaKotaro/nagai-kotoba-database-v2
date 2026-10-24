# 単語の登録(表層形+読みの一括登録)と、単語の修正(一覧・1語の修正・削除)。
# 新しい語の注釈(付与して公開する)はアノテーション・コンソール(Admin::AnnotationsController)が担い、
# 公開済みの語を直す流れはここに分けてある(Issue 108)。まとめて付ける・外すは
# Admin::BulkAnnotationsController・Admin::BulkDetachmentsController。
class Admin::WordsController < Admin::BaseController
  # 修正画面のチップ選択のマスタ(load_masters)と、一覧の条件の受け渡し(word_list_params・TAG_FILTER_KEYS)。
  include Admin::AnnotationChoices
  include Admin::WordListParams

  PER_PAGE = 100
  # 注釈状態の絞り込み(enum が生やす Word の同名スコープをそのまま使う)。
  # 未対応 / 保留 / 完了 の3状態。
  STATUS_FILTERS = %w[annotation_pending annotation_on_hold annotation_done].freeze

  before_action :set_word, only: :destroy
  before_action :set_word_with_senses, only: %i[edit update]

  # 一覧: 6,000語規模でも運用できるよう、検索(表層形・読み)+注釈状態+タグの絞り込み+ページネーション。
  # タグの絞り込みは、まとめて付ける・外すパネルと組み合わせて「絞り込み → 全選択 → 付け替え・外す」に使う。
  # 各行から、注釈済みの語は修正画面へ、未注釈の語はアノテーション・コンソールへ飛べる。
  def index
    @query = params[:q].to_s.strip
    @status = params[:status].presence_in(STATUS_FILTERS)
    @tag_filters = tag_filters_from_params
    @page = Pagination.page_number(params[:page])

    scope = filtered_words
    pagination = Pagination.new(page: @page, per_page: PER_PAGE, total_count: scope.count)
    @total_count = pagination.total_count
    @total_pages = pagination.total_pages
    @words = pagination.paginate(scope.includes(:word_senses).order(:id))
    load_masters_for_bulk
  end

  # step1: 表層形を箇条書きでまとめて貼り付ける。
  # 収録リクエスト一覧(Issue 75)の「一括登録へ渡す」から来た場合は、
  # 選択された言葉が箇条書きとして渡ってくるので初期値にする。
  def new
    @registration = BulkWordRegistration.new(text: params.permit(:text)[:text])
  end

  # step2: 箇条書きから読みを自動取得し、確認・編集できる画面を出す(重複判定はしない)。
  def readings
    @registration = BulkWordRegistration.new(text_params)
    unless @registration.analyzable?
      flash.now[:alert] = t("admin.words.bulk.empty")
      return render :new, status: :unprocessable_content
    end

    @rows = @registration.reading_rows
    render :readings
  end

  # step2(任意): 貼られた調査 JSON を MeCab の暫定読みと突き合わせ、確定候補を出す。
  def apply_research
    @registration = BulkWordRegistration.new(entries: entry_params, research_json: research_json_param)
    unless @registration.registerable?
      return redirect_to new_admin_word_path, alert: t("admin.words.bulk.empty")
    end

    @rows = @registration.merge_research
    flash.now[:alert] = t("admin.words.bulk.readings.research_error") if @registration.research_error?
    render :readings
  end

  # step3: 確定した読みで重複・類似を判定し、行の除外を選べる画面を出す。
  def duplicates
    @registration = BulkWordRegistration.new(entries: entry_params)
    unless @registration.registerable?
      return redirect_to new_admin_word_path, alert: t("admin.words.bulk.empty")
    end

    @analyzed = @registration.analyze_duplicates
    render :duplicates
  end

  # 登録: 除外されなかったエントリ(表層形+読み)を登録する。
  def create
    @registration = BulkWordRegistration.new(entries: entry_params)
    unless @registration.registerable?
      return redirect_to new_admin_word_path, alert: t("admin.words.bulk.empty")
    end

    @result = @registration.register
    if @result.errors.empty?
      redirect_to admin_words_path,
                  notice: t("admin.words.bulk.created", count: @result.created, skipped: @result.skipped)
    else
      # 正常な行は登録済み。エラー行を示す(貼り付け画面に結果を表示)。
      flash.now[:alert] = t("admin.words.bulk.partial")
      @registration = BulkWordRegistration.new
      render :new, status: :unprocessable_content
    end
  end

  # 1語の修正(Issue 108)。注釈フォームはコンソールと同じ部品を使うが、保存しても注釈状態(公開)・
  # キュー・Claude の提案・引き継ぎ(スティッキー)に触れず、来たときの一覧(word_list_params)へ戻る。
  def edit
    @word.word_senses.build if @word.word_senses.empty?
    load_masters
  end

  def update
    if @word.update(word_params)
      redirect_to admin_words_path(word_list_params), notice: t("admin.words.updated", surface: @word.surface)
    else
      load_masters
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @word.destroy
    redirect_to admin_words_path, notice: t("admin.words.destroyed")
  end

  private

  def set_word
    @word = Word.find(params[:id])
  end

  # 修正画面は語義の関連を辿って描く(コンソールの set_word と同じ先読み)。
  def set_word_with_senses
    @word = Word.includes(word_senses: %i[word_origins word_sense_features word_sense_variants])
                .find(params[:id])
  end

  # 許可属性の集合はコンソール・デッキと共有する(Admin::AnnotationQueue::WORD_ATTRIBUTES)。
  def word_params
    params.require(:word).permit(*Admin::AnnotationQueue::WORD_ATTRIBUTES)
  end

  # 一覧の絞り込み(キーワード + 注釈状態 + タグ)。
  def filtered_words
    scope = Word.all
    scope = scope.keyword(@query) if @query.present?
    scope = scope.public_send(@status) if @status
    # タグは語義に付くため、条件に合致する語義を持つ語へサブクエリで絞る(join の重複を避ける)。
    scope = scope.where(id: tag_filtered_senses.select(:word_id)) if @tag_filters.any?
    scope
  end

  # 正の整数が指定されたタグ条件だけを { キー => id } で集める。特徴の該当部分は文字列のまま加える。
  def tag_filters_from_params
    filters = TAG_FILTER_KEYS.each_with_object({}) do |key, collected|
      id = params[key].to_i
      collected[key] = id if id.positive?
    end
    target = params[FEATURE_TARGET_KEY].to_s.strip
    filters[FEATURE_TARGET_KEY] = target if target.present?
    filters
  end

  # タグ条件をすべて満たす(AND)語義の Relation。
  # ジャンルは、選んだジャンルと配下の全階層(Genre#self_and_descendant_ids)へ広げて絞り込む。見つからない id は
  # そのまま渡す(0 件になる)。公開検索(WordSenseSearch#genre_filter_ids)は配下の小分類だけに広げ、見つからない id は
  # 404 にするので定義は別だが、語義のジャンルは小分類だけ(WordSense#genre_must_be_small)なので、正しいデータでは
  # 結果は同じ。管理一覧は、検証を通らない語義(大・中分類が付いたもの)も拾えるよう、この定義のままにする(C3-18b)。
  def tag_filtered_senses
    senses = WordSense.all
    if (genre_id = @tag_filters[:genre_id])
      genre = Genre.find_by(id: genre_id)
      senses = senses.with_genre_ids(genre ? genre.self_and_descendant_ids : genre_id)
    end
    senses = senses.with_part_of_speech(@tag_filters[:part_of_speech_id]) if @tag_filters[:part_of_speech_id]
    senses = senses.with_entity_type(@tag_filters[:entity_type_id]) if @tag_filters[:entity_type_id]
    senses = senses.with_word_origin(@tag_filters[:word_origin_id]) if @tag_filters[:word_origin_id]
    if @tag_filters[:linguistic_feature_id] || @tag_filters[FEATURE_TARGET_KEY]
      # 特徴の行の選び方は「まとめて外す」(BulkDetachment)と共有する
      features = WordSenseFeature.matching(linguistic_feature_id: @tag_filters[:linguistic_feature_id],
                                           target: @tag_filters[FEATURE_TARGET_KEY])
      senses = senses.where(id: features.select(:word_sense_id))
    end
    senses
  end

  # まとめて付ける・外すパネル(Issue 37・108)のチップ選択と、タグ絞り込みのセレクトで使うマスタ一式。
  def load_masters_for_bulk
    load_masters
    # タグ絞り込みのジャンル・セレクトは大→中→小の全階層から選べるようにする。
    @all_genres = Genre.order(:name).to_a
  end

  # step1 の入力(箇条書きの貼り付けテキスト)。
  def text_params
    params.require(:bulk_word_registration).permit(:text)
  end

  # エントリ配列(表層形+読み、step3 以降は除外フラグ _exclude つき)。
  def entry_params
    params.require(:bulk_word_registration).permit(entries: %i[surface reading _exclude])[:entries]
  end

  # step2 の任意入力: 調査 JSON(貼り付けテキスト)。
  def research_json_param
    params.require(:bulk_word_registration).permit(:research_json)[:research_json]
  end
end
