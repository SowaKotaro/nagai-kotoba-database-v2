class HomeController < ApplicationController
  # トップページは全世界に公開する（未認証でも閲覧可）。
  allow_unauthenticated_access only: :index

  def index
  end
end
