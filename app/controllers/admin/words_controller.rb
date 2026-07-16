# 単語の登録(表層形+読みの一括登録)と、一覧・削除。
# 表層形の訂正やジャンル・品詞などの付与はアノテーション・コンソール(Admin::AnnotationsController)が担う。
class Admin::WordsController < Admin::BaseController
  PER_PAGE = 100
  # 注釈状態の絞り込み(enum が生やす Word の同名スコープをそのまま使う)。
  # 未対応 / 保留 / 完了 の3状態。
  STATUS_FILTERS = %w[annotation_pending annotation_on_hold annotation_done].freeze
  # タグ絞り込み(語義に付いたジャンル・品詞・エンティティ・語種)。
  # 一括適用パネルと組み合わせて「絞り込み → 全選択 → 付け替え」のバルク運用に使う。
  TAG_FILTER_KEYS = %i[genre_id part_of_speech_id entity_type_id word_origin_id].freeze

  before_action :set_word, only: :destroy

  # 一覧: 6,000語規模でも運用できるよう、検索(表層形・読み)+注釈状態+タグの絞り込み+ページネーション。
  # 各行から /admin/annotations/:id へ直接飛べる(ピンポイント・アノテーション)。
  def index
    @query = params[:q].to_s.strip
    @status = params[:status].presence_in(STATUS_FILTERS)
    @tag_filters = tag_filters_from_params
    @page = [ params[:page].to_i, 1 ].max

    scope = filtered_words
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @words = scope.includes(:word_senses)
                  .order(:id)
                  .limit(PER_PAGE)
                  .offset((@page - 1) * PER_PAGE)
    load_masters_for_bulk
  end

  # step1: 表層形を箇条書きでまとめて貼り付ける。
  def new
    @registration = BulkWordRegistration.new
  end

  # step2: 箇条書きから読みを自動取得し、確認・編集できる画面を出す(重複判定はしない)。
  def readings
    @registration = BulkWordRegistration.new(text_params)
    unless @registration.analyzable?
      flash.now[:alert] = t("admin.words.bulk.empty")
      return render :new, status: :unprocessable_entity
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
      render :new, status: :unprocessable_entity
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

  # 一覧の絞り込み(キーワード + 注釈状態 + タグ)。
  def filtered_words
    scope = Word.all
    scope = scope.keyword(@query) if @query.present?
    scope = scope.public_send(@status) if @status
    # タグは語義に付くため、条件に合致する語義を持つ語へサブクエリで絞る(join の重複を避ける)。
    scope = scope.where(id: tag_filtered_senses.select(:word_id)) if @tag_filters.any?
    scope
  end

  # 正の整数が指定されたタグ条件だけを { キー => id } で集める。
  def tag_filters_from_params
    TAG_FILTER_KEYS.each_with_object({}) do |key, filters|
      id = params[key].to_i
      filters[key] = id if id.positive?
    end
  end

  # タグ条件をすべて満たす(AND)語義の Relation。
  # ジャンルは大・中分類を選んでも配下の小分類へ展開して絞り込む(公開検索と同じ意味論)。
  def tag_filtered_senses
    senses = WordSense.all
    if (genre_id = @tag_filters[:genre_id])
      genre = Genre.find_by(id: genre_id)
      senses = senses.with_genre_ids(genre ? genre.self_and_descendant_ids : genre_id)
    end
    senses = senses.with_part_of_speech(@tag_filters[:part_of_speech_id]) if @tag_filters[:part_of_speech_id]
    senses = senses.with_entity_type(@tag_filters[:entity_type_id]) if @tag_filters[:entity_type_id]
    senses = senses.with_word_origin(@tag_filters[:word_origin_id]) if @tag_filters[:word_origin_id]
    senses
  end

  # 一括適用パネル(Issue 37)のチップ選択と、タグ絞り込みのセレクトで使うマスタ一式。
  def load_masters_for_bulk
    @word_origins = WordOrigin.order(:name)
    @parts_of_speech = PartOfSpeech.order(:name)
    @entity_types = EntityType.order(:name)
    @large_genres = Genre.large.order(:name)
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
