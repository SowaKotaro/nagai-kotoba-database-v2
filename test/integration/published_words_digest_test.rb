require "test_helper"

# 全件を1レスポンスに書き出す重い出力(sitemap.xml / llms-full.txt)の版(PublishedWordsDigest)。
# 版は公開語の最終更新「日」に畳んであり、同じ日のアノテーションでは作り直さない
# (畳んでいないと保存のたびに全件の再組み立てが走り、その間 Puma が塞がる。docs/performance-report.md)。
class PublishedWordsDigestTest < ActionDispatch::IntegrationTest
  PATHS = %w[/sitemap.xml /llms-full.txt].freeze

  test "版が変わっていなければ 304 を返す" do
    PATHS.each do |path|
      get path
      assert_response :success
      etag = response.headers["ETag"]
      assert etag.present?, "#{path} が ETag を返さない"

      get path, headers: { "If-None-Match" => etag }
      assert_response :not_modified, "#{path} が 304 にならない"
      assert_empty response.body
    end
  end

  test "同じ日の語義の保存では版が変わらない(アノテーション中に作り直しを誘発しない)" do
    # 語義の保存は touch: true で words.updated_at を動かすが、版の指紋は日単位に畳んである
    etags = etags_on(Time.zone.local(2026, 8, 6, 10, 5))

    travel_to Time.zone.local(2026, 8, 6, 18, 40) do
      word_senses(:murder).update!(meaning: "更新した意味")

      PATHS.each do |path|
        get path, headers: { "If-None-Match" => etags[path] }
        assert_response :not_modified, "#{path} が同じ日の保存で作り直された"
      end
    end
  end

  test "日をまたいで公開されれば版が変わり、新しい語が載る" do
    # 版は「今日が何日か」ではなくデータの最終更新日で決まる。翌日に保存があって初めて作り直す
    etags = etags_on(Time.zone.local(2026, 8, 6, 10, 5))

    travel_to Time.zone.local(2026, 8, 7, 9, 30) do
      word = Word.create!(surface: "翌日に公開した語", annotated_at: Time.current)
      word.word_senses.create!(reading: "ヨクジツニコウカイシタゴ")

      PATHS.each do |path|
        get path, headers: { "If-None-Match" => etags[path] }
        assert_response :success, "#{path} が翌日の公開で作り直されない"
        assert_includes response.body, "/words/#{word.id}"
      end
    end
  end

  private

  # 公開語の最終更新を time の日に揃え、その時点の各出力の ETag を控える。
  def etags_on(time)
    travel_to time do
      Word.update_all(updated_at: Time.current)
      PATHS.index_with do |path|
        get path
        response.headers["ETag"]
      end
    end
  end
end
