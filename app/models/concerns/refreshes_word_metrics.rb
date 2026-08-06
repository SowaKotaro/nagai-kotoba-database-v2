# 語義まわりのレコードが変わったら、その語(words)の代表値を焼き直す。
#
# 一覧の並び替えとランキングの指標は words のカラムに非正規化してある(WordSenseMetrics)。
# 元データは word_senses と、その別表記・言語学的特徴なので、それらの作成・更新・削除の
# たびに焼き直さないと順位が古いままになる。
#
# トランザクションが確定してから走らせる(after_commit)。ロールバックした変更で
# 代表値だけ書き換わるのを防ぐため、また集計を確定後の DB から読むため。
# 取り込む側は resolve_metrics_word_id で「どの語の代表値か」を返すこと。
module RefreshesWordMetrics
  extend ActiveSupport::Concern

  included do
    # 削除後は関連を辿れなくなるので、消える前に対象の語 id を控えておく。
    before_destroy :remember_metrics_word_id
    after_commit :refresh_word_metrics
  end

  private

  def refresh_word_metrics
    WordSenseMetrics.refresh!([ metrics_word_id ].compact)
  end

  def remember_metrics_word_id
    @metrics_word_id = resolve_metrics_word_id
  end

  def metrics_word_id
    @metrics_word_id || resolve_metrics_word_id
  end
end
