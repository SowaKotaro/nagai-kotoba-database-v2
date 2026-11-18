# SNS の自動投稿の文面(3 つの SNS で同じ形。docs/sns-autopost-setup.md §0)。
#
#   寿限無寿限無五劫の擦り切れ
#   ジュゲムジュゲムゴコウノスリキレ（16文字）
#
# 本文にはサイトの URL を入れない(X の API は URL を含む投稿の料金が高い)。単語詳細へのリンクは、
# Bluesky と Threads だけが返信(Link)で付ける。読みと文字数は代表語義(Word#primary_sense)のもの。
# 種別: 値オブジェクト（DB に触れない）。
module SnsPostText
  # X の上限(重み付きの字数)。3 つの SNS で最も厳しいので、本文はこれに収まる語だけを出す
  # (Bluesky は 300 字、Threads は 500 字。X は和文 1 字を 2 と数えるので、和文なら 140 字まで)。
  X_WEIGHTED_LIMIT = 280
  # X が 1 と数える文字の範囲(twitter-text の設定 v3。ほかは 2)。絵文字は 2 字ぶん以上に数えるが、上限より手前で止まる側なので構わない。
  X_LIGHT_RANGES = [ 0..4351, 8192..8205, 8208..8223, 8242..8247 ].freeze
  # リンクのカードの説明(Bluesky)の長さ。
  LINK_DESCRIPTION_LENGTH = 200

  # 返信に付けるリンク(Bluesky のカードの題・説明・画像も持つ。image は PNG のバイト列か nil)。
  Link = Data.define(:url, :title, :description, :image)
  Message = Data.define(:body, :link)

  module_function

  # 語義を読み込んだ語(includes(:word_senses))を渡す。
  def body(word)
    sense = word.primary_sense
    I18n.t("sns_posts.body", surface: word.surface, reading: sense.reading, length: sense.reading_length)
  end

  def fits?(word) = x_weight(body(word)) <= X_WEIGHTED_LIMIT

  def x_weight(text)
    text.unicode_normalize(:nfc).each_char.sum { |char| X_LIGHT_RANGES.any? { it.cover?(char.ord) } ? 1 : 2 }
  end

  def message(word, image: nil)
    url = SiteUrl.absolute(Rails.application.routes.url_helpers.word_path(word))
    description = word.primary_sense.meaning.to_s.squish.truncate(LINK_DESCRIPTION_LENGTH)
    Message.new(body: body(word), link: Link.new(url:, title: word.surface, description:, image:))
  end
end
