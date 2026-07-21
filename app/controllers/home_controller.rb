class HomeController < ApplicationController
  # トップページは全世界に公開する（未認証でも閲覧可）。
  allow_unauthenticated_access only: :index

  RECENT_WORDS_LIMIT = 5
  RANKING_LIMIT = 10

  def index
    # 公開統計は毎リクエスト COUNT を3本発行していた。短TTLでキャッシュする(Issue 26)。
    stats = Rails.cache.fetch("home/stats", expires_in: 1.hour) do
      {
        words: Word.annotated.count,
        senses: WordSense.published.count,
        genres: Genre.small.count,
        # 「長い言葉のデータベース」の性格を一言で示す指標。小数第1位まで。
        average_reading_length: WordSense.published.average(:reading_length)&.to_f&.round(1)
      }
    end
    @word_count = stats[:words]
    @sense_count = stats[:senses]
    @genre_count = stats[:genres]
    @average_reading_length = stats[:average_reading_length]
    @recent_words = Word.annotated
                        .includes(word_senses: [ :part_of_speech, :entity_type ])
                        .order(created_at: :desc, id: :desc)
                        .limit(RECENT_WORDS_LIMIT)
    # 最長ランキング(読みが長い順)。サイト最大のフックなので新着より上に置く。
    @longest_words = Word.annotated
                         .includes(word_senses: [ :part_of_speech, :entity_type ])
                         .order(WordSort.new("length_desc").order_clause)
                         .limit(RANKING_LIMIT)
    @featured_word = featured_word
  end

  private

  # 「今日の一語」: 日付から決まる語(日替わり・同じ日は同じ語)。注釈済みから選ぶ。
  def featured_word
    return nil if @word_count.zero?

    Word.annotated.includes(:word_senses).order(:id).offset(Date.current.jd % @word_count).first
  end
end
