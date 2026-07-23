class HomeController < ApplicationController
  # トップページは全世界に公開する（未認証でも閲覧可）。
  allow_unauthenticated_access only: :index

  RECENT_WORDS_LIMIT = 5
  RANKING_LIMIT = 10

  def index
    # 公開統計は毎リクエスト COUNT を3本発行していた。短TTLでキャッシュする(Issue 26)。
    # 「今月の」を含むのでキー自体に年月を持たせ、月をまたいだ瞬間に作り直す。
    stats = Rails.cache.fetch("home/stats/#{Date.current.strftime('%Y-%m')}", expires_in: 1.hour) do
      {
        words: Word.annotated.count,
        senses: WordSense.published.count,
        genres: Genre.small.count,
        # 更新が続いていることが一目で分かる指標(統計ページ「今月の新収録」と同じ定義)。
        monthly_new: Word.annotated.where(created_at: Time.current.all_month).count
      }
    end
    @word_count = stats[:words]
    @sense_count = stats[:senses]
    @genre_count = stats[:genres]
    @monthly_new_count = stats[:monthly_new]
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
