# 拡張: 拡張待ちの語を /expand 用に書き出し、結果を取り込む。取り込んだ語(元の語と集めた語)は
# 仕分けに系統ごとに並ぶので、取り込んだら仕分けの画面へ移る。
class Admin::Candidates::ExpansionsController < Admin::Candidates::BaseController
  def show
    load_stage
  end

  def import
    run_import(WordCandidateExpansionImport, admin_candidates_triage_path)
  end

  private

  def load_stage
    @export = WordCandidateExport.new("expand")
  end
end
