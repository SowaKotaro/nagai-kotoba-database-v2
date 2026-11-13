# 検索エンジン向けのサイトマップを動的生成する(Issue 15)。誰でも閲覧可。
# sitemap.xml は公開(注釈済み)の全単語 + 主要な静的ページ、sitemap-facets.xml はインデックスを許可している
# 単一条件の一覧(ファセット面)を列挙する。分けてあるのは、Search Console がサイトマップごとに登録状況を
# 集計するので、ファセット面だけの登録数を単語詳細と混ぜずに追うため(docs/seo-plan.md §5 C-2)。
#
# sitemap.xml の出力は語数に比例して重い(1万語規模で 1.4 秒。ほぼ全部が XML の組み立てで、SQL は 20ms 程度)。
# Puma は1プロセス・MRI は GIL なので、この1本が走っている間はサイト全体が止まる。
# クローラは遠慮なく取りに来るため、
#   1. 条件付きGET: 版が変わっていなければ本文を組み立てず 304 を返す
#   2. それでも組み立てるときは XML ごとキャッシュする(同時再生成も抑える)
# の二段で、リクエストのたびに再生成しないようにする。ファセット面のほうは軽いが、同じ作りに揃える
# (面の増減も公開語の版に従うので、反映は最大 1 日遅れる。PublishedWordsDigest)。
class SitemapsController < ApplicationController
  include PublishedWordsDigest

  allow_unauthenticated_access only: %i[show facets]

  def show
    render_cached_sitemap("sitemap/v1") do
      # loc/lastmod だけを最小カラムで取得(1万語規模でも1ファイルに収まる)。
      @words = Word.annotated.select(:id, :updated_at)
      render_to_string(template: "sitemaps/show", formats: :xml, layout: false)
    end
  end

  def facets
    render_cached_sitemap("sitemap-facets/v1") do
      @facets = IndexableFacets.for_sitemap
      render_to_string(template: "sitemaps/facets", formats: :xml, layout: false)
    end
  end

  private

  # 版が変わっていなければ 304、変わっていれば本文をキャッシュから(無ければブロックで組み立てて)返す。
  # キャッシュキーの接頭辞は出力ごとに分ける(形を変えたら版を上げる)。
  def render_cached_sitemap(key_prefix, &)
    cache_key = "#{key_prefix}/#{published_words_digest}"
    return unless stale?(etag: cache_key, last_modified: published_words_last_modified, public: true)

    body = Rails.cache.fetch(cache_key, expires_in: PublishedWordsDigest::CACHE_TTL,
                                        race_condition_ttl: PublishedWordsDigest::RACE_CONDITION_TTL, &)
    # クローラの取得は日次で十分。CDN/プロキシにもキャッシュさせる。
    expires_in PublishedWordsDigest::CACHE_TTL, public: true
    render plain: body, content_type: "application/xml"
  end
end
