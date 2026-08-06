require "test_helper"

class SitemapsControllerTest < ActionDispatch::IntegrationTest
  HOST = "https://nagai-kotoba-database.jp".freeze

  test "sitemap.xml は未認証で取得でき XML を返す" do
    get "/sitemap.xml"
    assert_response :success
    assert_match %r{application/xml|text/xml}, response.media_type
    assert_match "http://www.sitemaps.org/schemas/sitemap/0.9", response.body
  end

  test "sitemap に静的ページと公開(注釈済み)単語が本番ホストの絶対URLで並ぶ" do
    get "/sitemap.xml"

    assert_includes response.body, "<loc>#{HOST}/</loc>"
    assert_includes response.body, "<loc>#{HOST}/words</loc>"
    assert_includes response.body, "<loc>#{HOST}/words/#{words(:abc_murder).id}</loc>"
    # 更新日時が lastmod として入る
    assert_select_xml_has_lastmod
  end

  test "未注釈の語は sitemap に含めない" do
    get "/sitemap.xml"
    assert_not_includes response.body, "/words/#{words(:pending_haruhi).id}<"
    assert_not_includes response.body, "/words/#{words(:pending_haruhi).id}</loc>"
  end

  test "sitemap ルートは /sitemap.xml を生成する" do
    assert_equal "/sitemap.xml", sitemap_path
  end

  # --- 条件付きGET(組み立てが重いので、変わっていなければ本文を作らない) ---

  test "版が変わっていなければ 304 を返す" do
    get "/sitemap.xml"
    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?

    get "/sitemap.xml", headers: { "If-None-Match" => etag }
    assert_response :not_modified
    assert_empty response.body
  end

  test "同じ日の語義の保存では版が変わらない(アノテーション中に再生成を誘発しない)" do
    # 語義の保存は touch: true で words.updated_at を動かすが、指紋は日単位に畳んである。
    # 畳んでいないと、1語アノテーションするたびに全件の再組み立てが走る。
    travel_to Time.zone.local(2026, 8, 6, 10, 5) do
      Word.update_all(updated_at: Time.current) # 版の基準をこの日に揃える
      get "/sitemap.xml"
      @etag = response.headers["ETag"]
    end

    travel_to Time.zone.local(2026, 8, 6, 18, 40) do
      word_senses(:murder).update!(meaning: "更新した意味")

      get "/sitemap.xml", headers: { "If-None-Match" => @etag }
      assert_response :not_modified
    end
  end

  test "日をまたいで公開されれば版が変わり、新しい語が載る" do
    travel_to Time.zone.local(2026, 8, 6, 10, 5) do
      Word.update_all(updated_at: Time.current)
      get "/sitemap.xml"
      @etag = response.headers["ETag"]
    end

    travel_to Time.zone.local(2026, 8, 7, 9, 30) do
      word = Word.create!(surface: "新しく公開した語", annotated_at: Time.current)

      get "/sitemap.xml", headers: { "If-None-Match" => @etag }
      assert_response :success
      assert_includes response.body, "<loc>#{HOST}/words/#{word.id}</loc>"
    end
  end

  private

  def assert_select_xml_has_lastmod
    assert_match %r{<lastmod>\d{4}-\d{2}-\d{2}}, response.body
  end
end
