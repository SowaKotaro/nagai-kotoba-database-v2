class HomeController < ApplicationController
  # トップページは全世界に公開する（未認証でも閲覧可）。
  allow_unauthenticated_access only: :index

  RECENT_WORDS_LIMIT = 5

  def index
    # 公開統計・一覧は注釈済み(公開対象)の語だけを数える・見せる。
    @word_count = Word.annotated.count
    @sense_count = WordSense.published.count
    @genre_count = Genre.small.count
    @recent_words = Word.annotated.includes(:word_senses).order(created_at: :desc, id: :desc).limit(RECENT_WORDS_LIMIT)
    @featured_word = featured_word
  end

  private

  # 「今日の一語」: 日付から決まる語(日替わり・同じ日は同じ語)。注釈済みから選ぶ。
  def featured_word
    return nil if @word_count.zero?

    Word.annotated.includes(:word_senses).order(:id).offset(Date.current.jd % @word_count).first
  end
end
