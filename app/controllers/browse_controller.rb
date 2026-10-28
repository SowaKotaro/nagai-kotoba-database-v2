# 50音・読みの長さの索引ページ(Issue 22)。誰でも閲覧できる。
# 定番のブラウズ導線(あかさたな索引・文字数別)を件数つきで単語一覧へリンクする。
# 50音は先頭と末尾(しりとりの次の一手)、読みの長さは文字数とモーラ数(作詞などで拍を数えるとき)を切り替えて出す。
class BrowseController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    # 先頭文字・読みの文字数はインデックス済みの生成カラムだが、GROUP BY は公開語義の
    # 全件走査なので語数に比例して重くなる(開発 DB を 10 倍にした 1 万 7 千語で、ページの SQL が 75ms。
    # 2026-08-07 の計測。docs/history/performance-report.md §3.1)。
    # 件数は少し古くても導線として困らないため PublishedSenseCounts でキャッシュする。
    @first_char_counts = PublishedSenseCounts.by_first_char
    @last_char_counts = PublishedSenseCounts.by_last_char
    @reading_length_counts = PublishedSenseCounts.by_reading_length
    @mora_counts = PublishedSenseCounts.by_mora_count
    # 50音表と長さのタグを件数の濃淡(ヒート)で塗るための、表ごとの最大値。0除算を避けるため 0 で埋める。
    @max_counts = {
      first_char: @first_char_counts.values.max || 0,
      last_char: @last_char_counts.values.max || 0,
      reading_length: @reading_length_counts.values.max || 0,
      mora_count: @mora_counts.values.max || 0
    }
  end
end
