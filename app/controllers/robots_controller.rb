# robots.txt を配信する。Sitemap 行のホストを環境設定(canonical_host)と
# 連動させるため、public/ の静的ファイルではなく動的に生成する。
class RobotsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @host = Rails.application.config.x.canonical_host
    expires_in 1.day, public: true
    render layout: false, content_type: "text/plain"
  end
end
