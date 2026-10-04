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
                        .order(annotated_at: :desc, id: :desc)
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
    @featured_word = featured_word
  end

  private

  # 「今日の一語」: 日付から決まる語(日替わり・同じ日は同じ語)。注釈済みから選ぶ。
  def featured_word
    return nil if @word_count.zero?

    # ジャンル・エンティティ・品詞・語種まで見せるので、1語ぶんとはいえ個別に引かないよう先読みする
    Word.annotated
        .includes(word_senses: [ { genre: { parent: :parent } }, :entity_type, :part_of_speech, :word_origins ])
        .order(:id)
        .offset(Date.current.jd % @word_count)
        .first
  end
end
