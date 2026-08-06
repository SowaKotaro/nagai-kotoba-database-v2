# 検索エンジン向けの sitemap.xml を動的生成する(Issue 15)。誰でも閲覧可。
# 公開(注釈済み)の全単語 + 主要な静的ページを列挙する。
#
# 出力は語数に比例して重い(1万語規模で 1.4 秒。ほぼ全部が XML の組み立てで、SQL は 20ms 程度)。
# Puma は1プロセス・MRI は GIL なので、この1本が走っている間はサイト全体が止まる。
# クローラは遠慮なく取りに来るため、
#   1. 条件付きGET: 版が変わっていなければ本文を組み立てず 304 を返す
#   2. それでも組み立てるときは XML ごとキャッシュする(同時再生成も抑える)
# の二段で、リクエストのたびに再生成しないようにする。
class SitemapsController < ApplicationController
  include PublishedWordsDigest

  allow_unauthenticated_access only: :show

  CACHE_TTL = 1.day

  def show
    return unless stale?(etag: cache_key, last_modified: published_words_last_modified, public: true)

    body = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL,
                                        race_condition_ttl: PublishedWordsDigest::RACE_CONDITION_TTL) { render_sitemap }
    # クローラの取得は日次で十分。CDN/プロキシにもキャッシュさせる。
    expires_in CACHE_TTL, public: true
    render plain: body, content_type: "application/xml"
  end

  private

  def cache_key = "sitemap/v1/#{published_words_digest}"

  def render_sitemap
    # 絶対URLの基点は本番ホスト(request のホストではなく canonical を使う)。
    @host = Rails.application.config.x.canonical_host
    # loc/lastmod だけを最小カラムで取得(1万語規模でも1ファイルに収まる)。
    @words = Word.annotated.select(:id, :updated_at)
    render_to_string(template: "sitemaps/show", formats: :xml, layout: false)
  end
end
