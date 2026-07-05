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
  # 語種とは word_sense_origins を介した多対多(混種語に対応し複数付与できる)。
  has_many :word_sense_origins, dependent: :destroy
  has_many :word_origins, through: :word_sense_origins
  # 別表記(この語義にだけ付く別の表記。読みも変わりうる)。
  has_many :word_sense_variants, dependent: :destroy
  # 管理画面から特徴(該当部分つき)・語種・別表記をネストして登録・編集する。
  # 空行はスキップ、_destroy で削除可。
  accepts_nested_attributes_for :word_sense_features, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :word_sense_origins, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :word_sense_variants, allow_destroy: true, reject_if: :all_blank

  validates :reading, presence: true
  validate :genre_must_be_small

  # 公開対象。注釈済み(word.annotated_at あり)の語にぶら下がる語義だけ。
  scope :published, -> { joins(:word).where.not(words: { annotated_at: nil }) }

  # --- 検索・絞り込み用スコープ(生成カラム/インデックスを活用。Issue 9) ---
  # キーワード(表層形・読みの部分一致)。ワイルドカードはエスケープする。
  scope :keyword, lambda { |text|
    pattern = "%#{sanitize_sql_like(text)}%"
    joins(:word).where("words.surface LIKE :pattern OR word_senses.reading LIKE :pattern", pattern: pattern)
  }
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

  # 読み(reading)由来の派生値は常に reading から導出する(手入力させない)。
  # vowel_pattern は rhythm_pattern から作るため、rhythm_pattern の後に生成する。
  before_validation :assign_reading_derivations

  private

  def assign_reading_derivations
    self.rhythm_pattern = RhythmPattern.call(reading)
    self.vowel_pattern = VowelPattern.call(rhythm_pattern)
    self.mora_count = MoraCount.call(reading)
  end

  # genre は必ず小分類(末端)を指す運用。大・中分類は登録できない。
  def genre_must_be_small
    return if genre.blank?

    errors.add(:genre, :must_be_small) unless genre.small?
  end
end
