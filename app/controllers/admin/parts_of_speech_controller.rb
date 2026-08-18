# 品詞マスタのその場追加。
class Admin::PartsOfSpeechController < Admin::BaseController
  include InlineMasterCreatable

  def create
    create_inline_master(PartOfSpeech.all)
  end
end
