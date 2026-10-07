# サイトの絶対 URL の単一の正。起点は config.x.canonical_host(環境変数 CANONICAL_HOST。既定は本番)。
# request のホストではなく常にこれを使う(canonical・OGP・sitemap・robots・フィード・JSON API・llms で
# 同じ URL を出す)。テストは既定値を CANONICAL_HOST(test_helper)で固定している。
# 種別: 値オブジェクト（DB に触れない）。
module SiteUrl
  # og:image の既定カード(public/og-default.png。script/og_default.py で作る)。
  # 単語の共有カードを焼けないときも、ここへ回す(Words::ShareCardsController)。
  DEFAULT_OG_IMAGE_PATH = "/og-default.png".freeze

  module_function

  # スキーム付きの起点("https://nagai-kotoba-database.jp")。設定の名前は host だがスキームを含む。
  def origin = Rails.application.config.x.canonical_host

  # スキームを除いた裸のホスト("nagai-kotoba-database.jp")。共有カードの標識だけが使う。
  def host = URI.parse(origin).host

  # パス("/words/1")に起点を前置した絶対 URL。
  def absolute(path) = "#{origin}#{path}"
end
