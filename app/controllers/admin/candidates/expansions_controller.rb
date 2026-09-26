# 拡張: 拡張待ちの語を /expand 用に書き出し、結果を取り込む。取り込んだ語(元の語と集めた語)は
# 仕分けに系統ごとに並ぶので、取り込んだら仕分けの画面へ移る。
# 書き出しは一度に渡す語数を指定できる(Claude Code の利用上限に当たらないよう、数十語ずつ回すため)。
class Admin::Candidates::ExpansionsController < Admin::Candidates::BaseController
  # 一度に渡す語数の既定(オーナーの運用は 30 語ずつ)と上限。
  EXPORT_DEFAULT_LIMIT = 30
  EXPORT_MAX_LIMIT = 1000

  def show
    load_stage
  end

  def import
    run_import(WordCandidateExpansionImport, admin_candidates_triage_path, waiting: "expanding")
  end

  private

  def load_stage
    @limit = (params[:limit].presence || EXPORT_DEFAULT_LIMIT).to_i.clamp(1, EXPORT_MAX_LIMIT)
    @export = WordCandidateExport.new("expand", limit: @limit)
  end
end
