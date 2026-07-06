# LLM 向けのサイト案内 /llms.txt を配信する(Issue 24)。誰でも閲覧可。
# 内容は About(収録基準・ライセンス)と文言を共有する。
class LlmsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @host = Rails.application.config.x.canonical_host
    expires_in 1.day, public: true
    render layout: false, content_type: "text/plain"
  end
end
