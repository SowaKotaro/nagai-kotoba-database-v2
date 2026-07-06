require "test_helper"

# 静的エラーページ(Issue 32)の内容チェック。
# public/*.html は本番でのみ配信されるため、ファイル内容で日本語化・ブランド化を担保する。
class ErrorPagesTest < ActionDispatch::IntegrationTest
  def page(name) = File.read(Rails.root.join("public", name))

  test "404 は日本語・ブランド色で、主要ページへの導線がある" do
    html = page("404.html")
    assert_includes html, "ページが見つかりません"
    assert_includes html, 'lang="ja"'
    assert_includes html, "#C43A1E"          # 朱
    assert_includes html, 'href="/"'
    assert_includes html, 'href="/words"'
    assert_includes html, 'href="/search"'
    assert_not_includes html, "rails-default-error-page"
  end

  test "422 は日本語・ブランド化されている" do
    html = page("422.html")
    assert_includes html, "リクエストを処理できませんでした"
    assert_includes html, 'lang="ja"'
    assert_not_includes html, "rails-default-error-page"
  end

  test "500 は日本語・ブランド化されている" do
    html = page("500.html")
    assert_includes html, "サーバーでエラーが発生しました"
    assert_includes html, 'lang="ja"'
    assert_not_includes html, "rails-default-error-page"
  end
end
