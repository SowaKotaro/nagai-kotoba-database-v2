# 管理一覧で選択した語へ、共通属性(ジャンル・エンティティ・品詞・語種)と意味のテンプレ文を
# まとめて適用するフォームオブジェクト(Issue 37)。
# 同質な語群(例: 同じ作品のキャラクター名)を1回の操作でアノテーションするために使う。
#   - 指定された項目だけを上書きし、空欄の項目は各語の現状を保つ。
#   - 適用対象は単一語義の語のみ。複数語義の語は同音異義語への誤爆を防ぐためスキップして数える。
#   - 「注釈済みにする」は選択式(既定 OFF。確定事項4)。意味まで揃うテンプレ適用なら即完了にできる。
#   - 全体を1トランザクションで適用し、途中で失敗したら全体を巻き戻す。
class BulkAnnotation
  include ActiveModel::Model

  attr_accessor :genre_id, :entity_type_id, :part_of_speech_id, :meaning_template
  attr_reader :word_ids, :word_origin_ids, :mark_annotated

  validate :words_selected
  validate :attribute_given

  # 適用結果の集計。applied=適用した語数, skipped=複数語義(または語義なし)でスキップした語数。
  Result = Struct.new(:applied, :skipped, keyword_init: true)

  def word_ids=(values)
    @word_ids = Array(values).map(&:to_i).reject(&:zero?)
  end

  def word_origin_ids=(values)
    @word_origin_ids = Array(values).reject(&:blank?).map(&:to_i)
  end

  def mark_annotated=(value)
    @mark_annotated = ActiveModel::Type::Boolean.new.cast(value)
  end

  # 選択された語のうち単一語義の語だけに、指定された項目を適用する。
  def apply
    words = Word.includes(word_senses: :word_origins).where(id: word_ids)
    targets, skipped = words.partition { |word| word.word_senses.size == 1 }

    Word.transaction do
      targets.each { |word| apply_to(word) }
    end

    Result.new(applied: targets.size, skipped: skipped.size)
  end

  private

  def apply_to(word)
    sense = word.word_senses.first
    sense.genre_id = genre_id if genre_id.present?
    sense.entity_type_id = entity_type_id if entity_type_id.present?
    sense.part_of_speech_id = part_of_speech_id if part_of_speech_id.present?
    sense.word_origin_ids = word_origin_ids if word_origin_ids.present?
    sense.meaning = meaning_template if meaning_template.present?
    sense.save!

    return unless mark_annotated

    word.mark_annotated
    word.save!
  end

  def words_selected
    errors.add(:base, :no_words) if word_ids.blank?
  end

  def attribute_given
    return if [ genre_id, entity_type_id, part_of_speech_id, meaning_template ].any?(&:present?) ||
              word_origin_ids.present?

    errors.add(:base, :no_attributes)
  end
end
