# 語義まわりのレコードが変わったら、その語(words)の代表値を焼き直す。
#
# 一覧の並び替えとランキングの指標は words のカラムに非正規化してある(WordSenseMetrics)。
# 元データは word_senses と、その別表記・言語学的特徴なので、それらの作成・更新・削除の
# たびに焼き直さないと順位が古いままになる。
#
# トランザクションが確定してから走らせる(after_commit)。ロールバックした変更で
# 代表値だけ書き換わるのを防ぐため、また集計を確定後の DB から読むため。
# 取り込む側は resolve_metrics_word_id で「どの語の代表値か」を返すこと。
#
# すべての commit(作成・更新・削除)で発火する(on: で絞っていない)。意味だけの更新でも、ネストした保存で
# 同じ語を件数ぶん焼き直しても、焼き直しは冪等なので結果は同じ。語義を別の語へ付け替える経路は想定していない
# (resolve_metrics_word_id は新しい word_id だけを返すので、元の語の代表値が古いまま残る)。
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
