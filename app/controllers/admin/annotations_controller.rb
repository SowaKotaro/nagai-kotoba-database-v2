# 高速アノテーション・コンソール。1語を大きく表示し、語義・語種・ジャンル・品詞・
# エンティティ・言語学的特徴・別表記を素早く付与して「保存して次へ」で流す。
# キューは words.annotated_at が未セット(未注釈)の語を id 順に辿る。
class Admin::AnnotationsController < Admin::BaseController
  before_action :set_word, only: %i[show update]

  # 最初の未注釈へ誘導。無ければ完了画面(index ビュー)を出す。
  def index
    first = Word.unannotated.order(:id).first
    redirect_to admin_annotation_path(first) if first
  end

  def show
    @word.word_senses.build if @word.word_senses.empty?
    load_masters
    set_navigation
  end

  def update
    @word.assign_attributes(annotation_params)
    @word.mark_annotated
    if @word.save
      next_word = Word.unannotated.where.not(id: @word.id).order(:id).first
      redirect_to(next_word ? admin_annotation_path(next_word) : admin_annotations_path,
                  notice: t("admin.annotations.saved"))
    else
      load_masters
      set_navigation
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_word
    @word = Word.includes(word_senses: %i[word_origins word_sense_features word_sense_variants])
                .find(params[:id])
  end

  # チップ選択で使うマスタ一式。
  def load_masters
    @word_origins = WordOrigin.order(:name)
    @parts_of_speech = PartOfSpeech.order(:name)
    @entity_types = EntityType.order(:name)
    @linguistic_features = LinguisticFeature.order(:name)
    @large_genres = Genre.large.order(:name)
  end

  # キューの残数と、スキップ(次の未注釈)・戻る(直前の語)のリンク先。
  def set_navigation
    @remaining = Word.unannotated.count
    @skip_word = Word.unannotated.where("id > ?", @word.id).order(:id).first ||
                 Word.unannotated.where.not(id: @word.id).order(:id).first
    @prev_word = Word.where("id < ?", @word.id).order(id: :desc).first
  end

  # 語種は多対多(word_origin_ids)、ジャンル/品詞/エンティティは belongs_to の *_id、
  # 特徴・別表記はネスト属性。表層形(surface)の訂正もここで受ける(Issue 36: 編集画面を
  # コンソールへ統合。char_type_pattern は before_validation で再生成される)。
  def annotation_params
    params.require(:word).permit(
      :surface,
      word_senses_attributes: [
        :id, :_destroy, :reading, :meaning, :genre_id, :entity_type_id, :part_of_speech_id,
        { word_origin_ids: [],
          word_sense_features_attributes: %i[id _destroy linguistic_feature_id target target_reading],
          word_sense_variants_attributes: %i[id _destroy surface reading] }
      ]
    )
  end
end
