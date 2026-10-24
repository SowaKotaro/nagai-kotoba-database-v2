# 単語の修正の一覧で選んだ語から、指定した値(言語学的特徴・ジャンル・エンティティ・品詞・語種)を
# まとめて外すフォームオブジェクト(Issue 108)。まとめて付ける(BulkAnnotation)の逆向き。
#   - 「指定した値が付いている語義から、その値だけを外す」。値を持たない語義には触れないので、
#     複数語義の語も対象にする(BulkAnnotation が複数語義の語を飛ばすのは、値を上書きして同音異義語へ誤爆するため)。
#   - 特徴は該当部分(表記)を添えると、その該当部分に付いたものだけを外す。空欄なら、その特徴をすべて外す。
#     行の選び方は WordSenseFeature.matching(一覧の絞り込みと同じ定義)。
#   - ジャンルは、指定したジャンルとその配下が付いた語義から外す。
#   - 注釈状態(公開・未公開)は変えない。全体を1トランザクションで行い、途中で失敗したら全体を巻き戻す。
# 種別: 書き込み処理。
class BulkDetachment
  include ActiveModel::Model

  attr_accessor :linguistic_feature_id, :genre_id, :entity_type_id, :part_of_speech_id
  attr_reader :word_ids, :word_origin_ids, :feature_target

  validate :words_selected
  validate :value_given
  validate :feature_given_with_target

  # 結果の集計。words=何かを外した語の数, removed=外した値の延べ数(語義ごと・特徴の行ごとに数える)。
  Result = Struct.new(:words, :removed, keyword_init: true)

  def word_ids=(values)
    @word_ids = Array(values).map(&:to_i).reject(&:zero?)
  end

  def word_origin_ids=(values)
    @word_origin_ids = Array(values).reject(&:blank?).map(&:to_i)
  end

  # 一覧の絞り込みの値をそのまま受けることもあるので、前後の空白を落とす(BulkAnnotation と同じ扱い)。
  def feature_target=(value)
    @feature_target = value.to_s.strip.presence
  end

  def apply
    detached = []

    Word.transaction do
      detached.concat(detach_features)
      detached.concat(detach_origins)
      detached.concat(clear_column(:genre_id, genre_ids)) if genre_id.present?
      detached.concat(clear_column(:entity_type_id, entity_type_id)) if entity_type_id.present?
      detached.concat(clear_column(:part_of_speech_id, part_of_speech_id)) if part_of_speech_id.present?
      # 特徴・語種の行(中間テーブル)は消しても語を touch しないので、詳細ページの HTTP キャッシュ
      # (Word#cache_dependencies)が古い内容のまま 304 を返さないよう、語の updated_at を動かす。
      # touch_all はコールバックを通らないが、動かすのは updated_at だけで、派生値には関わらない。
      Word.where(id: detached.uniq).touch_all if detached.any?
    end

    Result.new(words: detached.uniq.size, removed: detached.size)
  end

  private

  # 選んだ語の語義。
  def senses
    WordSense.where(word_id: word_ids)
  end

  # 消した行の数だけ、その行の語の id を返す(以下の detach_*・clear_column も同じ形で返す)。
  # destroy! は1行ずつ: 特徴の数は代表値として words に焼いてあり、after_commit で焼き直す(RefreshesWordMetrics)。
  def detach_features
    return [] if linguistic_feature_id.blank?

    WordSenseFeature.matching(linguistic_feature_id: linguistic_feature_id, target: feature_target)
                    .where(word_sense_id: senses.select(:id))
                    .includes(:word_sense)
                    .map { |feature| feature.destroy!.word_sense.word_id }
  end

  def detach_origins
    return [] if word_origin_ids.blank?

    WordSenseOrigin.where(word_origin_id: word_origin_ids, word_sense_id: senses.select(:id))
                   .includes(:word_sense)
                   .map { |origin| origin.destroy!.word_sense.word_id }
  end

  # 列が指定の値(ジャンルは配下も含めた id の集合)の語義だけを、未設定に戻す。
  def clear_column(column, values)
    senses.where(column => values).map do |sense|
      sense.update!(column => nil)
      sense.word_id
    end
  end

  # 指定したジャンルと配下の全階層。見つからない id はそのまま渡す(0 件になる)。
  def genre_ids
    Genre.find_by(id: genre_id)&.self_and_descendant_ids || genre_id
  end

  def words_selected
    errors.add(:base, :no_words) if word_ids.blank?
  end

  def value_given
    return if [ linguistic_feature_id, genre_id, entity_type_id, part_of_speech_id ].any?(&:present?) ||
              word_origin_ids.present?

    errors.add(:base, :no_values)
  end

  # 該当部分だけを書いて特徴を選び忘れると、何も外さずに終わる(該当部分は特徴の絞り込みでしかない)。
  def feature_given_with_target
    errors.add(:base, :target_without_feature) if feature_target.present? && linguistic_feature_id.blank?
  end
end
