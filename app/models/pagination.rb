# 一覧のページ送りの計算(ページ番号の正規化・総ページ数・このページの範囲)。
# 公開の単語一覧・管理の単語一覧・管理の収録リクエスト一覧が共有する。
# 前後のリンクのマークアップは各画面が持つ(まとめるのは計画書 §7.7)。
# 種別: 値オブジェクト（DB に触れない。範囲は渡された Relation に limit/offset を足すだけ）。
class Pagination
  attr_reader :page, :per_page, :total_count

  # ?page= の値を 1 以上のページ番号にする(数字でない・0 以下は 1 ページ目)。
  def self.page_number(param)
    [ param.to_i, 1 ].max
  end

  def initialize(page:, per_page:, total_count:)
    @page = page
    @per_page = per_page
    @total_count = total_count
  end

  # 総ページ数。0 件でも 1(空の 1 ページ目を出す)。
  def total_pages
    [ (total_count.to_f / per_page).ceil, 1 ].max
  end

  def offset
    (page - 1) * per_page
  end

  def paginate(scope)
    scope.limit(per_page).offset(offset)
  end
end
