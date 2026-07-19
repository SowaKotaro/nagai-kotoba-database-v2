# 公開統計ページ「蔵版目録」(Issue 34 / docs/stats.md)。誰でも閲覧できる。
# 集計は SiteStatistics がまとめて行い、Rails.cache に1日置く(毎日再集計)。
class StatsController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    @stats = SiteStatistics.fetch
  end
end
