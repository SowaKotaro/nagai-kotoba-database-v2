# サイトの恒久ページ(About・プライバシーポリシー等)。誰でも閲覧できる静的な内容。
class PagesController < ApplicationController
  allow_unauthenticated_access only: %i[about privacy]

  # 標識の2行目に置く収録語数。毎リクエスト COUNT を打つほどの値ではないので1日置く。
  ABOUT_CACHE_TTL = 1.day

  def about
    @word_count = Rails.cache.fetch("pages/about/word_count", expires_in: ABOUT_CACHE_TTL) do
      Word.annotated.count
    end
  end

  # プライバシーポリシー(Issue 42)。GA4 による外部送信情報の公表ページ
  # (改正電気通信事業法の外部送信規律への対応)。
  def privacy; end
end
