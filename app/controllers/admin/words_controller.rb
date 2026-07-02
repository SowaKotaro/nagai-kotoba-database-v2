# 単語(表層形)とその語義・言語学的特徴を1画面でまとめて登録・編集・削除する。
class Admin::WordsController < Admin::BaseController
  before_action :set_word, only: %i[edit update destroy]

  def index
    @words = Word.includes(:word_senses).order(:surface)
  end

  def new
    @word = Word.new
    @word.word_senses.build
  end

  def create
    @word = Word.new(word_params)
    if @word.save
      redirect_to admin_words_path, notice: t("admin.words.created")
    else
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

  # Word → 語義(word_senses) → 言語学的特徴(word_sense_features) の2段ネスト。
  # 許可した属性のみ受け付ける(Strong Parameters)。
  def word_params
    params.require(:word).permit(
      :surface,
      word_senses_attributes: [
        :id, :_destroy, :reading, :genre_id, :entity_type_id, :part_of_speech_id, :meaning,
        { word_sense_features_attributes: %i[id _destroy linguistic_feature_id target target_reading] }
      ]
    )
  end
end
