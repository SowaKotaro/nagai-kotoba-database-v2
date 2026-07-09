class WordSense < ApplicationRecord
  # 1つの表層形(word)に複数の語義がぶら下がる(同音異義語に対応)。
  # 語義の変更で word.updated_at を進め、詳細ページの fresh_when / sitemap の lastmod を正しくする(Issue 26)。
  belongs_to :word, touch: true
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
  # 読みの長さ(生成カラム reading_length)の範囲・完全一致。
  scope :reading_length_at_least, ->(n) { where(reading_length: n..) }
  scope :reading_length_at_most, ->(n) { where(reading_length: ..n) }
  scope :reading_length_is, ->(n) { where(reading_length: n) }
  # モーラ数の完全一致。
  scope :mora_count_is, ->(n) { where(mora_count: n) }
  # 先頭文字(生成カラム first_char)/末尾文字(Ruby 側で計算する last_char)。
  scope :first_char_is, ->(char) { where(first_char: char) }
  scope :last_char_is, ->(char) { where(last_char: char) }
  # 指定した語種を持つ語義(語種は多対多)。
  scope :with_word_origin, lambda { |id|
    where(id: WordSenseOrigin.where(word_origin_id: id).select(:word_sense_id))
  }
  # ヘボン式ローマ字(rhythm_pattern)の部分一致。ワイルドカードはエスケープする。
  scope :rhythm_containing, ->(text) { where("rhythm_pattern LIKE ?", "%#{sanitize_sql_like(text)}%") }
  # 母音パターン(vowel_pattern)の部分一致。押韻検索(母音の並びで韻を探す)に使う。
  scope :vowel_containing, ->(text) { where("vowel_pattern LIKE ?", "%#{sanitize_sql_like(text)}%") }
  # 文字種(words.char_type_pattern)で絞り込む。
  # partial:        真なら部分一致(LIKE %...%)、偽なら完全一致(=)。
  # case_sensitive: 真なら大文字小文字を区別する。カラムは utf8mb4_0900_ai_ci で
  #                 既定では A=a とみなすため、区別する時だけ utf8mb4_bin で厳密比較する。
  # ワイルドカードはエスケープする。
  scope :char_type_pattern_matching, lambda { |pattern, partial:, case_sensitive:|
    column = case_sensitive ? "words.char_type_pattern COLLATE utf8mb4_bin" : "words.char_type_pattern"
    if partial
      joins(:word).where("#{column} LIKE ?", "%#{sanitize_sql_like(pattern)}%")
    else
      joins(:word).where("#{column} = ?", pattern)
    end
  }
  # マスタでの絞り込み。
  scope :with_genre_ids, ->(ids) { where(genre_id: ids) }
  scope :with_part_of_speech, ->(id) { where(part_of_speech_id: id) }
  scope :with_entity_type, ->(id) { where(entity_type_id: id) }
  # 指定した言語学的特徴を持つ語義。
  scope :with_linguistic_feature, lambda { |id|
    where(id: WordSenseFeature.where(linguistic_feature_id: id).select(:word_sense_id))
  }

  # 読みは textarea 入力(折り返し表示)のため、混入した改行を先に除去する。
  before_validation :strip_reading_newlines
  # 読み(reading)由来の派生値は常に reading から導出する(手入力させない)。
  # vowel_pattern は rhythm_pattern から作るため、rhythm_pattern の後に生成する。
  before_validation :assign_reading_derivations

  private

  def strip_reading_newlines
    # 読みは空白を持たないため、混入した改行は除去して前後の空白も落とす。
    self.reading = reading.gsub(/[\r\n]+/, "").strip if reading
  end

  def assign_reading_derivations
    self.rhythm_pattern = RhythmPattern.call(reading)
    self.vowel_pattern = VowelPattern.call(rhythm_pattern)
    self.mora_count = MoraCount.call(reading)
    # last_char は SQL 生成カラムにできない事情があり Ruby 側で計算する(LastChar 参照)。
    self.last_char = LastChar.call(reading)
  end

  # genre は必ず小分類(末端)を指す運用。大・中分類は登録できない。
  def genre_must_be_small
    return if genre.blank?

    errors.add(:genre, :must_be_small) unless genre.small?
  end
end
