class AddReadingMetricsToWordSenses < ActiveRecord::Migration[8.1]
  def change
    # 読み(reading)からの派生値を追加する。
    #   mora_count    … モーラ数(拗音「きゃ」は1拍として数える。reading_length とは別軸)
    #   vowel_pattern … 母音パターン(rhythm_pattern から母音 aiueo のみ抽出。押韻の軸)
    # どちらも SQL では素直に書けないため rhythm_pattern と同様に Ruby 側(値オブジェクト)で
    # 生成し、WordSense の before_validation で自動セットする(生成カラムにはしない)。
    add_column :word_senses, :mora_count, :integer, null: true, comment: "モーラ数(拗音は1拍)"
    add_column :word_senses, :vowel_pattern, :string, null: true, limit: 1024,
                                             comment: "母音パターン(読みの母音のみ)"

    add_index :word_senses, :mora_count, name: "idx_word_senses_mora_count"
    # utf8mb4 のインデックスキー長制限対策で vowel_pattern は先頭191文字を対象にする。
    add_index :word_senses, :vowel_pattern, length: 191, name: "idx_word_senses_vowel_pattern"
  end
end
