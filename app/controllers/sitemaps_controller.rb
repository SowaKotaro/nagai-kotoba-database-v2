# 検索エンジン向けの sitemap.xml を動的生成する(Issue 15)。誰でも閲覧可。
# 公開(注釈済み)の全単語 + 主要な静的ページを列挙する。
class SitemapsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    # 絶対URLの基点は本番ホスト(request のホストではなく canonical を使う)。
    @host = Rails.application.config.x.canonical_host
    # loc/lastmod だけを最小カラムで取得(1万語規模でも1ファイルに収まる)。
    @words = Word.annotated.select(:id, :updated_at)
    # クローラの取得は日次で十分。CDN/プロキシにもキャッシュさせる。
    expires_in 1.day, public: true
  end
end
