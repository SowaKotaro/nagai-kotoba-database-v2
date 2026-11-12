# 公開側の llms-full.txt を curl で取り、調査の自動実行の重複照合に使う写し(ResearchCorpus)を更新するラッパー。
# 本番では使わない(ローカルの cron から rake research:auto で動く)。
#
# 手元の写しがあれば、その日時で条件付きに取る(-z)。サーバは Last-Modified / ETag に応じるので、更新が無ければ 304 で
# 何も届かない。-R で写しの日時を Last-Modified に揃え、次の比較を正しく効かせる。
# 届いた本文は一時ファイルに落とし、ResearchCorpus が読めた(冒頭の語数と見出しの数が合った)ときだけ差し替える
# (Cloudflare の確認画面など、200 で返る HTML を写しにしないため)。
#
# セキュリティ: コマンドは配列で渡してシェルを通さない。URL は SiteUrl の起点で、外部入力は混ざらない。
# 失敗(curl が無い・時間切れ・異常終了・中身が読めない)は :failed を返し、呼び出し側は古い写しのまま進む。
# 種別: 外部コマンドのラッパー（app/services には外部プロセスを起動するクラスだけを置く）。
class LlmsFullFetcher
  # 秒。全文はおよそ数 MB。
  TIMEOUT = 120

  def initialize(path, url: SiteUrl.absolute(Rails.application.routes.url_helpers.llms_full_path), timeout: TIMEOUT)
    @path = Pathname(path)
    @url = url
    @timeout = timeout
  end

  # :updated(差し替えた) / :not_modified(写しのまま) / :failed(取れなかった・中身が読めなかった)。
  def call
    FileUtils.mkdir_p(@path.dirname)
    partial = @path.dirname.join(".tmp-#{@path.basename}")
    FileUtils.rm_f(partial)
    return :failed unless system("curl", *arguments(partial), out: File::NULL, err: File::NULL)
    return :not_modified unless partial.exist? && partial.size.positive?
    return :failed unless ResearchCorpus.parse(partial.read)

    File.rename(partial, @path)
    :updated
  rescue SystemCallError
    :failed
  ensure
    FileUtils.rm_f(partial) if partial
  end

  private

  def arguments(partial)
    arguments = [ "--fail", "--silent", "--show-error", "--compressed", "--remote-time",
                  "--max-time", @timeout.to_s, "--output", partial.to_s ]
    arguments += [ "--time-cond", @path.to_s ] if @path.exist?
    arguments << @url
  end
end
