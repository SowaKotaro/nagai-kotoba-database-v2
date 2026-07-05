# 単語の登録(表層形+読みの一括登録)と、編集・削除。
# ジャンル・品詞などの付与はアノテーション・コンソール(Admin::AnnotationsController)が担う。
class Admin::WordsController < Admin::BaseController
  before_action :set_word, only: %i[edit update destroy]

  def index
    @words = Word.includes(:word_senses).order(:surface)
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

  def edit
  end

  def update
    if @word.update(word_params)
      redirect_to admin_words_path, notice: t("admin.words.updated")
    else
      render :edit, status: :unprocessable_entity
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

  # 編集は表層形と読みの訂正のみ(ジャンル等の付与はアノテーションに集約)。
  def word_params
    params.require(:word).permit(:surface, word_senses_attributes: %i[id _destroy reading])
  end
end
