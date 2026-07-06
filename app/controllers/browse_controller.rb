# 50音・読みの文字数の索引ページ(Issue 22)。誰でも閲覧できる。
# 定番のブラウズ導線(あかさたな索引・文字数別)を件数つきで単語一覧へリンクする。
class BrowseController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    # 先頭文字・読みの文字数はインデックス済みの生成カラム。集計は各1クエリで済む。
    # (キャッシュは Issue 26 で fresh_when/fragment とあわせて導入する)
    @first_char_counts = WordSense.published.group(:first_char).count
    # 50音表を件数の濃淡(ヒート)で塗るための最大値。0除算を避けるため別に持つ。
    @first_char_max = @first_char_counts.values.max || 0
    @reading_length_counts = WordSense.published.group(:reading_length).count
  end
end
