# 注釈フォーム(admin/annotations/_sense_fields)のチップ選択で使うマスタ一式。
# 1語コンソール・デッキ(Admin::AnnotationQueue 経由)と単語の修正(Admin::WordsController)が
# 同じフォームを描くので、選択肢の並びをここだけで持つ。
module Admin::AnnotationChoices
  extend ActiveSupport::Concern

  private

  def load_masters
    @word_origins = WordOrigin.order(:name)
    @parts_of_speech = PartOfSpeech.order(:name)
    @entity_types = EntityType.order(:name)
    @linguistic_features = LinguisticFeature.in_glossary_order
    @large_genres = Genre.large.order(:name)
  end
end
