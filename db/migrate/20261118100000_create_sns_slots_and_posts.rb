class CreateSnsSlotsAndPosts < ActiveRecord::Migration[8.1]
  def change
    # SNS の自動投稿(毎時)の枠。1 時間に 1 行で、その時刻に出す語を持つ。
    # 語は SNS をまたいで同じにするので、投稿(sns_posts)ではなく枠に持たせる。
    # round は「公開語を一巡するまで重ねない」ための何巡目か(SnsRotation)。
    create_table :sns_slots, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.datetime :slot_at, null: false, comment: "枠の時刻(正時)"
      t.bigint :word_id, comment: "出す語(語を消したら NULL)"
      t.integer :round, null: false, comment: "何巡目か(1 から)"

      t.timestamps

      # cron が同じ時刻に 2 回走っても、枠は 1 つしかできない。
      t.index :slot_at, unique: true, name: "idx_sns_slots_slot_at"
      t.index %i[round word_id], name: "idx_sns_slots_round_word"
      t.index :word_id, name: "idx_sns_slots_word"
    end

    # 枠ごと・SNS ごとの投稿。送る前に sending で行を作って、二重に送らない(SnsBroadcast)。
    create_table :sns_posts, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :sns_slot_id, null: false
      t.integer :platform, null: false, comment: "10:Bluesky 20:X 30:Threads"
      t.integer :status, null: false, default: 10, comment: "10:送信中 20:投稿済み 90:失敗"
      t.string :remote_id, limit: 255, comment: "SNS 側の投稿の ID(Bluesky は at:// の URI)"
      t.string :error_message, limit: 1000, comment: "失敗の理由(返信だけ失敗したときも残す)"
      t.datetime :posted_at, comment: "投稿できた時刻"

      t.timestamps

      t.index %i[sns_slot_id platform], unique: true, name: "idx_sns_posts_slot_platform"
    end

    add_foreign_key :sns_slots, :words, column: :word_id, on_delete: :nullify, name: "fk_sns_slots_word"
    add_foreign_key :sns_posts, :sns_slots, column: :sns_slot_id, on_delete: :cascade, name: "fk_sns_posts_slot"
  end
end
