# 単語の登録(表層形+読みの一括登録)と、編集・削除。
# ジャンル・品詞などの付与はアノテーション・コンソール(Admin::AnnotationsController)が担う。
class Admin::WordsController < Admin::BaseController
  before_action :set_word, only: %i[edit update destroy]

  def index
    @words = Word.includes(:word_senses).order(:surface)
  end

  # 登録: 表層形と読みをテキストエリアからまとめて入力する。
  def new
    @registration = BulkWordRegistration.new
  end

  def create
    @registration = BulkWordRegistration.new(registration_params)
    unless @registration.valid?
      return render :new, status: :unprocessable_entity
    end

    @result = @registration.register
    if @result.errors.empty?
      redirect_to admin_words_path,
                  notice: t("admin.words.bulk.created", count: @result.created, skipped: @result.skipped)
    else
      # 正常な行は登録済み。エラー行を示して再入力してもらう。
      flash.now[:alert] = t("admin.words.bulk.partial")
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

  # 一括登録の入力(貼り付けテキスト)。
  def registration_params
    params.require(:bulk_word_registration).permit(:text)
  end

  # 編集は表層形と読みの訂正のみ(ジャンル等の付与はアノテーションに集約)。
  def word_params
    params.require(:word).permit(:surface, word_senses_attributes: %i[id _destroy reading])
  end
end
