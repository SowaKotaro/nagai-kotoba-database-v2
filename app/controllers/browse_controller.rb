# 50音・読みの文字数の索引ページ(Issue 22)。誰でも閲覧できる。
# 定番のブラウズ導線(あかさたな索引・文字数別)を件数つきで単語一覧へリンクする。
class BrowseController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    # 先頭文字・読みの文字数はインデックス済みの生成カラムだが、GROUP BY は公開語義の
    # 全件走査なので語数に比例して重くなる(開発 DB を 10 倍にした 1 万 7 千語で、ページの SQL が 75ms。
    # 2026-08-07 の計測。docs/history/performance-report.md §3.1)。
    # 件数は少し古くても導線として困らないため PublishedSenseCounts でキャッシュする。
    @first_char_counts = PublishedSenseCounts.by_first_char
    # 50音表を件数の濃淡(ヒート)で塗るための最大値。0除算を避けるため別に持つ。
    @first_char_max = @first_char_counts.values.max || 0
    @reading_length_counts = PublishedSenseCounts.by_reading_length
  end
end
