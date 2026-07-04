class CreateWordSenseVariants < ActiveRecord::Migration[8.1]
  def change
    # 別表記。語義(word_sense)に対し 1:多。
    # 別表記は「その語義」にだけ付く(例:「バタフライエフェクト」の自然科学の語義には
    # 別表記「バタフライ効果」があるが、映画の語義には無い)。読みも変わりうるため保持する
    # (バタフライエフェクト → バタフライこうか)。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :word_sense_variants, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :word_sense_id, null: false
      t.string :surface, null: false, limit: 768, comment: "別表記の表層形 例: バタフライ効果"
      t.string :reading, null: true, limit: 768, comment: "別表記の読み(変わる場合) 例: バタフライこうか"
      t.string :note, null: true, comment: "任意メモ(旧字/略式 など)"

      t.timestamps

      # 同じ語義に同じ表記を二重登録させない。
      # utf8mb4 のインデックスキー長制限対策で surface は先頭191文字を対象にする。
      # (word_sense_id を先頭に含むため word_sense_id 単独の索引も兼ねる)
      t.index [ :word_sense_id, :surface ], unique: true, length: { surface: 191 },
              name: "uq_wsv_sense_surface"
    end

    add_foreign_key :word_sense_variants, :word_senses, column: :word_sense_id, name: "fk_wsv_word_sense"
  end
end
