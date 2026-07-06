module ApplicationHelper
  # <title> と og:title に使う共通のページタイトル。
  # ページ側が content_for(:title) を設定していればブランド名と連結する。
  def page_title
    content_for?(:title) ? "#{content_for(:title)} | #{t('layouts.brand')}" : t("layouts.brand")
  end

  # meta description / og:description。ページ側の content_for(:description) を優先し、
  # 無ければサイト既定の説明にフォールバックする。検索スニペット向けに1行・約120字に整える。
  def page_description
    raw = content_for?(:description) ? content_for(:description) : t("home.index.description")
    raw.to_s.squish.truncate(120)
  end

  # canonical と og:url。既定は本番ホスト + 現在のパス(クエリは含めない)。
  # ファセット等でパスを差し替えたいページは content_for(:canonical_path) を設定する(Issue 17)。
  def canonical_url
    path = content_for?(:canonical_path) ? content_for(:canonical_path).to_s : request.path
    absolute_site_url(path)
  end

  # og:image の絶対URL。ページ側の content_for(:og_image) を優先し、無ければ既定カード。
  def page_og_image
    path = content_for?(:og_image) ? content_for(:og_image).to_s : "/og-default.png"
    absolute_site_url(path)
  end

  # og:type。単語詳細などは content_for(:og_type) で "article" を指定できる。
  def page_og_type
    content_for?(:og_type) ? content_for(:og_type).to_s : "website"
  end

  private

  # サイトの正規ホストを前置した絶対URLを返す。
  def absolute_site_url(path)
    "#{Rails.application.config.x.canonical_host}#{path}"
  end
end
