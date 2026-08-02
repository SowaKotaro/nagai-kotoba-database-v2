class CreateWordRequests < ActiveRecord::Migration[8.1]
  def change
    # 公開側からの収録リクエスト(Issue 75)。送信1通 = word_requests、語1件 = word_request_items。
    # 1通に最大10語まで入るため、送信の技術メタデータは通側に1回だけ持たせる
    # (語行に重複させない)。レートリミットは「通」を数えるので、
    # 「1語を10回送った」と「10語を1回送った」を区別できる。
    create_table :word_requests, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :ip_address, limit: 45, null: false, comment: "送信元IP(IPv6 も入る長さ)。レートリミットと解析に使う"
      t.string :user_agent, limit: 512, comment: "ブラウザの種類(User-Agent)"
      t.string :referer, limit: 1024, comment: "直前のページ(Referer ヘッダ)"
      t.string :origin_path, limit: 1024, comment: "サイト内のどのページから来たか(検索0件 / About などの導線評価用)"

      t.timestamps

      # レートリミット判定(同一IPの直近N時間の通数)で毎回引く複合インデックス。
      t.index %i[ip_address created_at], name: "idx_word_requests_ip_created"
    end

    create_table :word_request_items, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :word_request_id, null: false
      # 読み・表層形まわりは清濁を区別する必要があるため as_ci(CLAUDE.md の例外規定)。
      t.string :surface, limit: 255, null: false, collation: "utf8mb4_0900_as_ci", comment: "リクエストされた表層形"
      t.string :reading, limit: 255, collation: "utf8mb4_0900_as_ci", comment: "リクエスト者が任意で入れた読み(カタカナ想定)"
      t.integer :status, null: false, default: 0, comment: "0:未着手 1:採用済み 2:保留 3:却下"
      t.string :admin_memo, limit: 1000, comment: "管理者メモ(却下理由など)"
      t.datetime :handled_at, comment: "ステータスを未着手から動かした時刻"

      t.timestamps

      t.index :word_request_id, name: "idx_word_request_items_request"
      t.index %i[status created_at], name: "idx_word_request_items_status_created"
      # 管理一覧で「同じ表層形が既に収録済みか」を引くため。長い表層形は prefix index。
      t.index :surface, length: 191, name: "idx_word_request_items_surface"
    end

    add_foreign_key :word_request_items, :word_requests, column: :word_request_id,
                    name: "fk_word_request_items_request"
  end
end
