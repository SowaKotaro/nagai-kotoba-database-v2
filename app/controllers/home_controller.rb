class HomeController < ApplicationController
  # トップページは全世界に公開する（未認証でも閲覧可）。
  allow_unauthenticated_access only: :index

  RECENT_WORDS_LIMIT = 5
  RANKING_LIMIT = 5

  def index
    # 看板の数(キャッシュの長さと、月の変わり目で作り直す理由は HomeStatistics)。
    stats = HomeStatistics.fetch
    @word_count = stats[:words]
    @sense_count = stats[:senses]
    @genre_count = stats[:genres]
    @monthly_new_count = stats[:monthly_new]
    # 新着はサイトに出てきた順(annotated_at = 注釈完了 = 公開)で並べる。新着 Atom フィード
    # (words#index の atom 形式。WordsController#feed_words)と同じ基準。
    @recent_words = Word.annotated
                        .includes(word_senses: [ :part_of_speech, :entity_type ])
                        .order(WordSort.new("created_desc").order_clause)
                        .limit(RECENT_WORDS_LIMIT)
    # 最長ランキング(読みが長い順)。ビューでは「読みが長い言葉」として新着の下に置く。
    @longest_words = Word.annotated
                         .includes(word_senses: [ :part_of_speech, :entity_type ])
                         .order(WordSort.new("length_desc").order_clause)
                         .limit(RANKING_LIMIT)
    # 看板に出す「最長の読み」。サイト最大のフックになる数で、下の「読みが長い言葉」の
    # 1 位と同じ値になる。@longest_words は読み込み済みなので追加のクエリは発行しない。
    # load してから first を取る。未読込のリレーションに first を呼ぶと LIMIT 1 の
    # 問い合わせが別に飛び、ビューで改めて RANKING_LIMIT 件を引き直すことになる。
    @longest_reading_length = @longest_words.load.first&.primary_sense&.reading_length
    # 今日の一語。選ぶときの語数は、看板と同じキャッシュした語数(理由は Word.featured_on)。
    @featured_word = Word.featured_on(Date.current, count: @word_count)
  end
end
