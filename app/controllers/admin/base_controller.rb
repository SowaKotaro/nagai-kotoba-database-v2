# 管理者専用コントローラの基底。ApplicationController が Authentication を include して
# いるため、Admin 配下の全アクションは既定で認証必須(管理者のみ)になる。
# 公開閲覧(Issue 8)はこの名前空間の外に置き、書き込み経路をここに閉じ込める。
# ※名前空間 Admin は Admin モデル(app/models/admin.rb)が保持する(Zeitwerk の明示的名前空間)。
class Admin::BaseController < ApplicationController
end
