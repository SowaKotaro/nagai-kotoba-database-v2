# 単語ごとの共有カード(og:image)。SNS やチャットのクローラが取りに来るので、誰でも取得できる。
# 焼けない環境(rsvg-convert・日本語の書体が無い)や焼けなかったときは、既定のカードへ回す。
class Words::ShareCardsController < ApplicationController
  allow_unauthenticated_access only: :show

  DEFAULT_CARD_PATH = "/og-default.png".freeze

  def show
    # 未注釈の語は公開しない(RecordNotFound → 404)。詳細ページと同じ。
    word = Word.annotated.includes(:word_senses).find(params[:word_id])
    card = WordShareCard.new(word)
    png = rendered_png(word, card)
    return redirect_to(DEFAULT_CARD_PATH) unless png

    # URL の版(v)が今の版と同じなら、この URL の中身は変わらない(表記や意匠が変われば版ごと URL が変わる)。
    # 版の違う・無い URL は古い共有などから来たものなので、今のカードを返しつつ短く持たせる。
    if params[:v] == card.digest
      expires_in 1.year, public: true, immutable: true
    else
      expires_in 1.hour, public: true
    end
    send_data png, type: "image/png", disposition: "inline"
  end

  private

  def rendered_png(word, card)
    return unless card.drawable? && ShareCardRenderer.available?

    ShareCardRenderer.new.fetch(name: "word-#{word.id}", version: card.digest, svg: card.svg)
  end
end
