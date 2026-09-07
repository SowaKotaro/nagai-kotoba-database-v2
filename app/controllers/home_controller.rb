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
        # 基準は annotated_at(公開日)。created_at は一括登録で下書きを作った日でしかなく、
        # 注釈を終えて公開した月とは限らないため、公開面の「収録日」には使わない。
        monthly_new: Word.annotated.where(annotated_at: Time.current.all_month).count
      }
    end
    @word_count = stats[:words]
    @sense_count = stats[:senses]
    @genre_count = stats[:genres]
    @monthly_new_count = stats[:monthly_new]
    # 新着はサイトに出てきた順(annotated_at = 注釈完了 = 公開)で並べる。新着 Atom フィード
    # (words#feed)と同じ基準。
    @recent_words = Word.annotated
                        .includes(word_senses: [ :part_of_speech, :entity_type ])
                        .order(annotated_at: :desc, id: :desc)
                        .limit(RECENT_WORDS_LIMIT)
    # 最長ランキング(読みが長い順)。サイト最大のフックなので新着より上に置く。
    @longest_words = Word.annotated
                         .includes(word_senses: [ :part_of_speech, :entity_type ])
                         .order(WordSort.new("length_desc").order_clause)
                         .limit(RANKING_LIMIT)
    # 看板に出す「最長の読み」。サイト最大のフックになる数で、下の「読みが長い言葉」の
    # 1 位と同じ値になる。@longest_words は読み込み済みなので追加のクエリは発行しない。
    # load してから first を取る。未読込のリレーションに first を呼ぶと LIMIT 1 の
    # 問い合わせが別に飛び、ビューで改めて 10 件を引き直すことになる。
    @longest_reading_length = @longest_words.load.first&.word_senses&.first&.reading_length
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
