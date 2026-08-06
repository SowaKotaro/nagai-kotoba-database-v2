# LLM 向けのサイト案内 /llms.txt と、その全文版 /llms-full.txt を配信する(Issue 24・73)。
# どちらも誰でも閲覧可。内容は About(収録基準・ライセンス)と文言を共有する。
class LlmsController < ApplicationController
  include PublishedWordsDigest

  allow_unauthenticated_access only: %i[show full]

  CACHE_TTL = 1.day

  def show
    @host = canonical_host
    expires_in CACHE_TTL, public: true
    render layout: false, content_type: "text/plain"
  end

  # 全文版。公開(注釈済み)の全語を1ファイルにまとめる。
  # 組み立ては語数に比例して重く(1万語規模で数秒)、その間 Puma(1プロセス・GIL)が
  # 塞がってサイト全体と管理画面が止まる。条件付きGETで「変わっていなければ本文を作らない」
  # ようにしたうえで、作った本文はキャッシュする。
  def full
    return unless stale?(etag: full_cache_key, last_modified: published_words_last_modified, public: true)

    body = Rails.cache.fetch(full_cache_key, expires_in: CACHE_TTL,
                                             race_condition_ttl: PublishedWordsDigest::RACE_CONDITION_TTL) { render_full }
    expires_in CACHE_TTL, public: true
    render plain: body, content_type: "text/plain"
  end

  private

  # 絶対URLの基点は本番ホスト(request のホストではなく canonical を使う)。
  def canonical_host = Rails.application.config.x.canonical_host

  # 公開語の最終更新日をキーにする。語義の更新は touch: true で words.updated_at を
  # 動かすので、語の追加・注釈・語義の編集はすべてキーに反映される。
  # 日単位に畳む理由は PublishedWordsDigest を参照(畳まないとアノテーション1回ごとに
  # 数秒の再生成が走り、管理画面の「保存して次へ」を巻き込んで待たせる)。
  def full_cache_key = "llms_full/v2/#{published_words_digest}"

  def render_full
    @host = canonical_host
    @generated_on = Date.current
    @word_count = Word.annotated.count
    # 語数が増えても一度に全件を抱えないよう、ビューは find_each で回す(id 順 = 登録順)。
    # 1語ぶんの表示に使う関連は words#show と同じ深さで先読みする。
    @words = Word.annotated.includes(
      word_senses: [
        { genre: { parent: :parent } }, :entity_type, :part_of_speech, :word_origins, :word_sense_variants,
        { word_sense_features: :linguistic_feature }
      ]
    )
    render_to_string(template: "llms/full", layout: false, formats: :text)
  end
end
