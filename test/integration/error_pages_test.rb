require "test_helper"

# 静的エラーページ(Issue 32)。public/*.html は本番でのみ配信され、CSS のパイプラインも通らないため、
# ファイルの中身で日本語化・ブランド化と、デザイントークン(文字色)との同期を確かめる。
class ErrorPagesTest < ActiveSupport::TestCase
  def page(name) = File.read(Rails.root.join("public", name))

  test "404・422・500 は日本語で、Rails 既定のページのままではない" do
    {
      "404.html" => "ページが見つかりません",
      "422.html" => "リクエストを処理できませんでした",
      "500.html" => "サーバーでエラーが発生しました"
    }.each do |name, heading|
      html = page(name)
      assert_includes html, heading, name
      assert_includes html, 'lang="ja"', name
      assert_not_includes html, "rails-default-error-page", name
    end
  end

  test "404 はトークンと同じ文字色でダークにも追従し、主要ページへの導線がある" do
    html = page("404.html")
    text_color = File.read(Rails.root.join("app/assets/stylesheets/tokens.css"))[/--text:\s*(#\h{6})/, 1]
    assert_includes html.downcase, text_color.downcase, "404.html の文字色が tokens.css の --text とずれている"
    assert_includes html, "prefers-color-scheme: dark"
    %w[/ /words /search].each { |path| assert_includes html, %(href="#{path}") }
  end
end
