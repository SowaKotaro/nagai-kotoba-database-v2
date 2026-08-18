# 語種マスタのその場追加(コンソールから画面遷移せずに選択肢を増やす)。
class Admin::WordOriginsController < Admin::BaseController
  include InlineMasterCreatable

  def create
    create_inline_master(WordOrigin.all)
  end
end
