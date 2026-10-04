# robots.txt を配信する。Sitemap 行の URL を環境設定(SiteUrl。config.x.canonical_host)と
# 連動させるため、public/ の静的ファイルではなく動的に生成する。
class RobotsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    expires_in 1.day, public: true
    render layout: false, content_type: "text/plain"
  end
end
