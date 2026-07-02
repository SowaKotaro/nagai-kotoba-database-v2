class HomeController < ApplicationController
  # トップページは全世界に公開する（未認証でも閲覧可）。
  allow_unauthenticated_access only: :index

  RECENT_WORDS_LIMIT = 5

  def index
    @word_count = Word.count
    @sense_count = WordSense.count
    @genre_count = Genre.small.count
    @recent_words = Word.includes(:word_senses).order(created_at: :desc, id: :desc).limit(RECENT_WORDS_LIMIT)
  end
end
