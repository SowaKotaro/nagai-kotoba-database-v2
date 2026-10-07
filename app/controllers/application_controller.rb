class ApplicationController < ActionController::Base
  include Authentication

  # ログイン中は、同じ URL でも HTML が違う(ヘッダーの管理リンクとログアウトのフォーム)。条件付き GET の版(ETag)に
  # ログインしていることを混ぜ、ログイン前にブラウザが持った版で 304 を返さないようにする。
  # ログインしていないときは何も足さない(nil は版に混ざらないので、公開側の ETag は変わらない)。
  etag { "authenticated" if authenticated? }
end
