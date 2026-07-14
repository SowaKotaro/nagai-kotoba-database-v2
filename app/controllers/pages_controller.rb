# サイトの恒久ページ(About・プライバシーポリシー等)。誰でも閲覧できる静的な内容。
class PagesController < ApplicationController
  allow_unauthenticated_access only: %i[about privacy]

  def about; end

  # プライバシーポリシー(Issue 42)。GA4 による外部送信情報の公表ページ
  # (改正電気通信事業法の外部送信規律への対応)。
  def privacy; end
end
