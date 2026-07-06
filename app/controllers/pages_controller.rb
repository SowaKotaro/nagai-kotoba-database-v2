# サイトの恒久ページ(About 等)。誰でも閲覧できる静的な内容。
class PagesController < ApplicationController
  allow_unauthenticated_access only: :about

  def about; end
end
