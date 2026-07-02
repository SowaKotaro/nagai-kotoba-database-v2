class WordSense < ApplicationRecord
  # 1つの表層形(word)に複数の語義がぶら下がる(同音異義語に対応)。
  belongs_to :word
  # genre_id は末端(小分類=level3)を指す。entity_type / part_of_speech は任意。
  belongs_to :genre, optional: true
  belongs_to :entity_type, optional: true
  belongs_to :part_of_speech, optional: true
  # 言語学的特徴とは word_sense_features を介した多対多。
  has_many :word_sense_features, dependent: :destroy
  has_many :linguistic_features, through: :word_sense_features
  # 管理画面から特徴(該当部分つき)をネストして登録・編集する。空行はスキップ、_destroy で削除可。
  accepts_nested_attributes_for :word_sense_features, allow_destroy: true, reject_if: :all_blank

  validates :reading, presence: true
  validate :genre_must_be_small

  # --- 検索・絞り込み用スコープ(生成カラム/インデックスを活用。Issue 9) ---
  # 読みの長さ(生成カラム reading_length)の範囲。
  scope :reading_length_at_least, ->(n) { where(reading_length: n..) }
  scope :reading_length_at_most, ->(n) { where(reading_length: ..n) }
  # 先頭/末尾文字(生成カラム first_char/last_char)。
  scope :first_char_is, ->(char) { where(first_char: char) }
  scope :last_char_is, ->(char) { where(last_char: char) }
  # 韻(rhythm_pattern)の部分一致。ワイルドカードはエスケープする。
  scope :rhythm_containing, ->(text) { where("rhythm_pattern LIKE ?", "%#{sanitize_sql_like(text)}%") }
  # 文字タイプ列(words.char_type_pattern)の完全一致。
  scope :char_type_pattern_is, ->(pattern) { joins(:word).where(words: { char_type_pattern: pattern }) }
  # マスタでの絞り込み。
  scope :with_genre_ids, ->(ids) { where(genre_id: ids) }
  scope :with_part_of_speech, ->(id) { where(part_of_speech_id: id) }
  scope :with_entity_type, ->(id) { where(entity_type_id: id) }
  # 指定した言語学的特徴を持つ語義。
  scope :with_linguistic_feature, lambda { |id|
    where(id: WordSenseFeature.where(linguistic_feature_id: id).select(:word_sense_id))
  }

  # rhythm_pattern は reading から常に導出する(手入力させない)。
  before_validation :assign_rhythm_pattern

  private

  def assign_rhythm_pattern
    self.rhythm_pattern = RhythmPattern.call(reading)
  end

  # genre は必ず小分類(末端)を指す運用。大・中分類は登録できない。
  def genre_must_be_small
    return if genre.blank?

    errors.add(:genre, :must_be_small) unless genre.small?
  end
end
