# 管理一覧で選択した語へ、共通属性(ジャンル・エンティティ・品詞・語種)と意味のテンプレ文を
# まとめて適用するフォームオブジェクト(Issue 37)。逆向き(まとめて外す)は BulkDetachment。
# 同質な語群(例: 同じ作品のキャラクター名)を1回の操作でアノテーションするために使う。
#   - 指定された項目だけを上書きし、空欄の項目は各語の現状を保つ。
#   - 適用対象は単一語義の語のみ。複数語義の語は同音異義語への誤爆を防ぐためスキップして数える。
#   - 言語学的特徴は、該当部分(表記と読み)の文字列を指定して足す(Issue 108)。表層形と読みの両方に
#     その文字列がある語だけに、表層形の最初の出現の位置で付ける。無い語は飛ばして数える。
#     既に同じ特徴・該当部分・位置が付いていれば足さない(何度押しても増えない)。
#   - 「注釈済みにする」は選択式(既定 OFF。docs/issues.md 確定事項 9)。意味まで揃うテンプレ適用なら即完了にできる。
#   - 全体を1トランザクションで適用し、途中で失敗したら全体を巻き戻す。
# 種別: 書き込み処理。
class BulkAnnotation
  include ActiveModel::Model

  attr_accessor :genre_id, :entity_type_id, :part_of_speech_id, :meaning_template, :linguistic_feature_id
  attr_reader :word_ids, :word_origin_ids, :mark_annotated, :feature_target, :feature_target_reading

  validate :words_selected
  validate :attribute_given
  validate :feature_target_given

  # 適用結果の集計。applied=適用した語数, skipped=複数語義(または語義なし)でスキップした語数,
  # feature_skipped=適用した語のうち、該当部分が表層形か読みに無く特徴を付けなかった語数。
  Result = Struct.new(:applied, :skipped, :feature_skipped, keyword_init: true)

  def word_ids=(values)
    @word_ids = Array(values).map(&:to_i).reject(&:zero?)
  end

  def word_origin_ids=(values)
    @word_origin_ids = Array(values).reject(&:blank?).map(&:to_i)
  end

  # 該当部分は文字列として表層形・読みに当てるので、貼り付けで混ざった前後の空白を落とす。
  def feature_target=(value)
    @feature_target = value.to_s.strip.presence
  end

  def feature_target_reading=(value)
    @feature_target_reading = value.to_s.strip.presence
  end

  def mark_annotated=(value)
    @mark_annotated = ActiveModel::Type::Boolean.new.cast(value)
  end

  # 選択された語のうち単一語義の語だけに、指定された項目を適用する。
  def apply
    words = Word.includes(word_senses: %i[word_origins word_sense_features]).where(id: word_ids)
    targets, skipped = words.partition { |word| word.word_senses.size == 1 }

    feature_skipped = 0
    Word.transaction do
      targets.each { |word| feature_skipped += 1 unless apply_to(word) }
    end

    Result.new(applied: targets.size, skipped: skipped.size, feature_skipped: feature_skipped)
  end

  private

  # 特徴を付けられなかったときだけ false を返す(特徴を指定していなければ true)。
  def apply_to(word)
    sense = word.primary_sense
    sense.genre_id = genre_id if genre_id.present?
    sense.entity_type_id = entity_type_id if entity_type_id.present?
    sense.part_of_speech_id = part_of_speech_id if part_of_speech_id.present?
    sense.word_origin_ids = word_origin_ids if word_origin_ids.present?
    sense.meaning = meaning_template if meaning_template.present?
    sense.save!
    feature_attached = linguistic_feature_id.blank? || attach_feature(word, sense)

    if mark_annotated
      word.mark_annotated
      word.save!
    end
    feature_attached
  end

  # 位置は表層形の最初の出現(0 始まり・コードポイント単位。WordSenseFeature#derive_target_start と同じ数え方)。
  def attach_feature(word, sense)
    reading_part = feature_target_reading.presence || feature_target
    start = word.surface.index(feature_target)
    return false if start.nil? || !sense.reading.include?(reading_part)

    sense.word_sense_features
         .create_with(target_reading: reading_part)
         .find_or_create_by!(linguistic_feature_id: linguistic_feature_id, target: feature_target, target_start: start)
    true
  end

  def words_selected
    errors.add(:base, :no_words) if word_ids.blank?
  end

  def attribute_given
    return if [ genre_id, entity_type_id, part_of_speech_id, meaning_template, linguistic_feature_id ].any?(&:present?) ||
              word_origin_ids.present?

    errors.add(:base, :no_attributes)
  end

  # 特徴は該当部分が無いと付けられない(どの文字に付くかが特徴の中身)。
  def feature_target_given
    errors.add(:base, :feature_without_target) if linguistic_feature_id.present? && feature_target.blank?
  end
end
