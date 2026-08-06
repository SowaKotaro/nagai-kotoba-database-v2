require "test_helper"

class LlmsControllerTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "llms.txt は未認証で取得でき text/plain を返す" do
    get "/llms.txt"
    assert_response :success
    assert_equal "text/plain", response.media_type
  end

  test "llms.txt にサイト概要・主要ページ・ライセンスが載る" do
    get "/llms.txt"
    body = response.body

    assert_includes body, I18n.t("layouts.brand")
    assert_includes body, "10文字以上"                       # 収録基準
    assert_includes body, "#{HOST}/words"
    assert_includes body, "#{HOST}/about"
    assert_includes body, "#{HOST}/sitemap.xml"
    assert_includes body, "CC BY 4.0"                        # ライセンス
    assert_includes body, "#{HOST}"                          # クレジットの URL
  end

  test "llms.txt から全文版(llms-full.txt)へ案内する" do
    get "/llms.txt"
    assert_includes response.body, "#{HOST}/llms-full.txt"
  end

  test "llms ルートは /llms.txt を生成する" do
    assert_equal "/llms.txt", llms_path
  end

  # --- 全文版(Issue 73) ---
  test "llms-full.txt は未認証で取得でき text/plain を返す" do
    get "/llms-full.txt"
    assert_response :success
    assert_equal "text/plain", response.media_type
  end

  test "llms-full.txt に公開語の見出し・URL・読み・属性が載る" do
    get "/llms-full.txt"
    body = response.body
    word = words(:abc_murder)
    sense = word_senses(:murder)

    assert_includes body, "### #{word.surface}"
    assert_includes body, "#{HOST}#{word_path(word)}"
    assert_includes body, "- 文字種: #{word.char_type_pattern}"
    assert_includes body, "- 読み: #{sense.reading}(#{sense.reading_length}字 / #{sense.mora_count}拍)"
    assert_includes body, "- 先頭文字 / 末尾文字: #{sense.first_char} / #{sense.last_char}"
    assert_includes body, "- 意味: #{sense.meaning}"
    assert_includes body, "- ジャンル: 文学 › 日本文学 › 小説"
    assert_includes body, "- 品詞: #{sense.part_of_speech.name}"
    assert_includes body, "- エンティティ: #{sense.entity_type.name}"
    # 別表記は「表記(読み)」の形で載る
    variant = word_sense_variants(:curry_variant)
    assert_includes body, "- 別表記: #{variant.surface}(#{variant.reading})"
  end

  test "llms-full.txt に未注釈語は載らない" do
    get "/llms-full.txt"
    assert_not_includes response.body, words(:pending_haruhi).surface
  end

  test "llms-full.txt は語義が複数ある語だけ語義見出しで区切る" do
    words(:curry).word_senses.create!(reading: "カレーライス", meaning: "米飯に掛ける料理")

    get "/llms-full.txt"

    curry_block = word_block(response.body, words(:curry).surface)
    assert_includes curry_block, "#### 語義1"
    assert_includes curry_block, "#### 語義2"
    # 語義が1つの語には語義見出しを出さない
    assert_not_includes word_block(response.body, words(:abc_murder).surface), "#### 語義"
  end

  test "llms-full.txt にライセンスと目次版・JSON API への案内が載る" do
    get "/llms-full.txt"
    body = response.body

    assert_includes body, "CC BY 4.0"
    assert_includes body, "#{HOST}/llms.txt"
    assert_includes body, "#{HOST}/words.json"
  end

  test "llms_full ルートは /llms-full.txt を生成する" do
    assert_equal "/llms-full.txt", llms_full_path
  end

  # --- 条件付きGET(全文の組み立ては語数に比例して重いので、変わっていなければ作らない) ---

  test "llms-full.txt は版が変わっていなければ 304 を返す" do
    get "/llms-full.txt"
    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?

    get "/llms-full.txt", headers: { "If-None-Match" => etag }
    assert_response :not_modified
    assert_empty response.body
  end

  test "同じ日の語義の保存では版が変わらない(アノテーション中に全文再生成を誘発しない)" do
    # 語義の保存は touch: true で words.updated_at を動かすが、版の指紋は日単位に畳んである。
    # 畳んでいないと、1語アノテーションするたびに全文の再組み立て(数秒)が走り、
    # その間 Puma(1プロセス)が塞がって管理画面の操作まで待たされる。
    travel_to Time.zone.local(2026, 8, 6, 10, 5) do
      Word.update_all(updated_at: Time.current) # 版の基準をこの日に揃える
      get "/llms-full.txt"
      @etag = response.headers["ETag"]
    end

    # 同じ日の夕方にもう1語保存しても版は動かない
    travel_to Time.zone.local(2026, 8, 6, 18, 40) do
      word_senses(:murder).update!(meaning: "更新した意味")

      get "/llms-full.txt", headers: { "If-None-Match" => @etag }
      assert_response :not_modified
    end
  end

  test "日をまたいで保存されれば版が変わって作り直す" do
    # 版は「今日が何日か」ではなくデータの最終更新日で決まる。同じ日の保存は
    # まとめて1版に畳まれ、翌日に保存があって初めて作り直す。
    travel_to Time.zone.local(2026, 8, 6, 10, 5) do
      Word.update_all(updated_at: Time.current)
      get "/llms-full.txt"
      @etag = response.headers["ETag"]
    end

    travel_to Time.zone.local(2026, 8, 7, 9, 30) do
      word_senses(:murder).update!(meaning: "更新した意味")

      get "/llms-full.txt", headers: { "If-None-Match" => @etag }
      assert_response :success
      assert_includes response.body, "更新した意味"
    end
  end

  private

  # 見出し語1語ぶんのブロック(次の「### 」の手前まで)を切り出す。
  # 語義見出し「#### 」は末尾の空白が無いので区切りには当たらない。
  def word_block(body, surface)
    start = body.index("### #{surface}")
    finish = body.index("\n### ", start + 1) || body.length
    body[start...finish]
  end
end
