# トップページ。サイト名の読みの円環・看板(検索と探し方の入口)・今日の一語・新着と読みが長い言葉・統計の数(docs/design.md §5.2)。
class HomeController < ApplicationController
  allow_unauthenticated_access only: :index

  RECENT_WORDS_LIMIT = 5
  RANKING_LIMIT = 5

  def index
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
    # 今日の一語。選ぶときの語数はキャッシュした語数(理由は Word.featured_on と HomeStatistics)。
    @featured_word = Word.featured_on(Date.current, count: HomeStatistics.word_count)
    # 数字で見る長い言葉。統計ページの数字の壁と同じ時点の数(集計一式ではなく、数字の壁だけの写しを読む)
    @figures = SiteStatistics.wall
  end
end
