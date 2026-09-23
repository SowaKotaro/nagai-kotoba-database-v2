class CreateWordCandidates < ActiveRecord::Migration[8.1]
  def change
    # 登録予定単語(登録前の前処理)。research/ の入出力ファイルを上書きする運用では
    # 「どの語がどの段階まで進んだか」が残らないため、段階をステータスとして DB に持たせる。
    # 流れは upload → expand → duplicate → notation → done。done の語を一括登録に貼る。
    # 不要にした語も消さずに残し、表層形のユニーク制約で「一度見た語」の集合を兼ねる
    # (expand / harvest からの再流入を取り込み時に弾くため)。
    create_table :word_candidates, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      # 読み・表層形まわりは清濁を区別する必要があるため as_ci(CLAUDE.md の例外規定)。
      t.string :surface, limit: 255, null: false, collation: "utf8mb4_0900_as_ci", comment: "現在の表層形(notation で置き換わる)"
      t.string :original_surface, limit: 255, null: false, collation: "utf8mb4_0900_as_ci", comment: "upload した時点の表層形"
      t.integer :status, null: false, default: 10,
                comment: "10:upload 20:expand 30:duplicate 40:notation 50:done 60:登録済み 80:要判断 85:重複 90:不要"
      t.bigint :seed_id, comment: "expand で増えた語の、元になった語"
      t.bigint :root_id, comment: "expand の系統の根(一覧を「元の語 → 増えた語」の順に並べるため。根自身は NULL)"
      t.bigint :word_id, comment: "一括登録で収録された語"
      t.integer :entry_score, limit: 1, comment: "notation の立項スコア 1〜5"
      t.string :confidence, limit: 10, comment: "notation の確からしさ high / medium / low"
      t.string :note, limit: 1000, comment: "メモ(不要にした理由・調査の注記など)"
      t.datetime :expanded_at, comment: "expand の結果を取り込んだ時刻(expand で増えた語は作成時刻)"
      t.datetime :notated_at, comment: "notation の結果を取り込んだ時刻"
      t.datetime :status_changed_at, comment: "ステータスを最後に動かした時刻"

      t.timestamps

      # 一度見た語の集合を兼ねる。長い表層形は prefix index。
      t.index :surface, unique: true, length: 191, name: "idx_word_candidates_surface"
      t.index %i[status id], name: "idx_word_candidates_status"
      t.index :seed_id, name: "idx_word_candidates_seed"
      t.index :root_id, name: "idx_word_candidates_root"
      t.index :word_id, name: "idx_word_candidates_word"
    end

    add_foreign_key :word_candidates, :word_candidates, column: :seed_id, on_delete: :nullify,
                    name: "fk_word_candidates_seed"
    add_foreign_key :word_candidates, :word_candidates, column: :root_id, on_delete: :nullify,
                    name: "fk_word_candidates_root"
    add_foreign_key :word_candidates, :words, column: :word_id, on_delete: :nullify,
                    name: "fk_word_candidates_word"
  end
end
