class Session < ApplicationRecord
  # 無操作がこの期間続いたセッションは失効させる(利用のたびに延長するスライディング方式)。
  LIFETIME = 2.weeks
  # updated_at(最終利用時刻)の更新はこの間隔まで間引き、毎リクエストの書き込みを避ける。
  ACTIVITY_REFRESH_INTERVAL = 1.hour

  belongs_to :admin

  scope :expired, -> { where(updated_at: ...LIFETIME.ago) }

  def expired?
    updated_at < LIFETIME.ago
  end

  # 最終利用時刻を更新する。間引き間隔内なら何もせず nil を返す(更新したら true)。
  def refresh_activity
    touch if updated_at < ACTIVITY_REFRESH_INTERVAL.ago
  end
end
