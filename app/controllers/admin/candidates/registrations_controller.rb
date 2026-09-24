# 登録待ち: 表記を確かめた語を /reading 用に書き出し、一括登録(読みの確認 = step2)へそのまま渡す。
# 一括登録で収録された語は、自動で登録済みになってここから消える(WordCandidate.register_for!)。
class Admin::Candidates::RegistrationsController < Admin::Candidates::BaseController
  def show
    @export = WordCandidateExport.new("reading")
  end
end
