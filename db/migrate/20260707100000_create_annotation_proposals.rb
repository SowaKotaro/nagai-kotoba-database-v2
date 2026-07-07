class CreateAnnotationProposals < ActiveRecord::Migration[8.1]
  def change
    # Claude Code の調査結果(アノテーション提案)の下書き置き場(Issue 38)。
    # 提案は公開面の元データ(word_senses)へ直接書かず、ここに置いてコンソールで
    # 人間が確認・修正して保存(承認)する。語ごとに1件で、再取り込みは上書き(冪等)。
    # 照合順序は日本語検索方針に合わせ utf8mb4_0900_ai_ci に統一する。
    create_table :annotation_proposals, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :word_id, null: false
      t.json :payload, null: false, comment: "提案本体(意味・ジャンルパス・エンティティ・品詞・語種・別表記・confidence・メモ)"
      t.integer :status, null: false, default: 0, comment: "0:pending 1:applied 2:dismissed"

      t.timestamps

      t.index :word_id, unique: true, name: "uq_annotation_proposals_word"
      t.index :status, name: "idx_annotation_proposals_status"
    end

    add_foreign_key :annotation_proposals, :words, column: :word_id, name: "fk_annotation_proposals_word"
  end
end
