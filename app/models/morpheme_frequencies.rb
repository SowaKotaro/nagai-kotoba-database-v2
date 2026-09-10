# 統計ページ §1「ワードクラウド」が読む、形態素の出現頻度(Issue 78)。
#
# 本番・CI に MeCab が無いため、頻度は**ローカルで事前集計してファイルに置く**。
# 更新は `bin/rails stats:morphemes`(lib/tasks/stats.rake)。本番はこのファイルを読むだけで、
# MeCab への依存を持ち込まない。
#
# 集計は元データから常に作り直せる導出データなので、テーブルは作らない
# (統計ページ本体が「統計テーブルを先行して作らない」方針なのと揃える)。
class MorphemeFrequencies
  DEFAULT_PATH = Rails.root.join("db/morpheme_frequencies.json")

  # 図に載せる件数(オーナー指示 2026-09-10 で 260 → 100)。
  # 全部載せると縦に伸びるばかりで、1つ1つの語が読めなくなる。
  DISPLAY_LIMIT = 100
  # この回数以上現れた形態素だけを載せる(1回だけの語は「繰り返し現れる部品」ではない)。
  MIN_COUNT = 2

  Entry = Struct.new(:text, :count, :weight, keyword_init: true) do
    # 最頻を 1.0、下限を 0.0 とした位置。活字の級数(font-size)に使う。
    def top? = weight >= 1.0
  end

  class << self
    # 集計ファイルの場所。テストから差し替えられるようにしている。
    def path = @path || DEFAULT_PATH

    def path=(value)
      @path = value && Pathname.new(value)
      reset!
    end

    # 見本に並べる形態素。頻度の多い順。
    def entries
      @entries ||= build_entries
    end

    # 集計時点の情報(生成日・対象語数)。見本の肩に添える。
    def metadata
      @metadata ||= data["metadata"] || {}
    end

    def available? = entries.any?

    # 集計結果を書き出す(rake タスクから呼ぶ)。
    def write!(counts, word_count:)
      payload = {
        "metadata" => {
          "generated_at" => Time.current.iso8601,
          "word_count" => word_count,
          "morpheme_count" => counts.size
        },
        "counts" => counts.sort_by { |text, count| [ -count, text ] }.to_h
      }
      path.write(JSON.pretty_generate(payload) + "\n")
      reset!
      payload["metadata"]
    end

    # テストや再読み込み用。
    def reset!
      @entries = nil
      @metadata = nil
      @data = nil
    end

    private

    def data
      @data ||= path.exist? ? JSON.parse(path.read) : {}
    rescue JSON::ParserError
      {}
    end

    def build_entries
      counts = data["counts"]
      return [] unless counts.is_a?(Hash)

      selected = counts.map { |text, count| [ text, count.to_i ] }
                       .select { |_, count| count >= MIN_COUNT }
                       .sort_by { |text, count| [ -count, text ] }
                       .first(DISPLAY_LIMIT)
      return [] if selected.empty?

      max = selected.first.last
      min = selected.last.last
      # 級数は頻度の位置(0.0〜1.0)で決める。全部同数なら一律で最大にする。
      #
      # 位置は**対数**で採る。頻度は一部の語だけが飛び抜ける分布なので、そのまま線形に
      # 割り当てると大多数(2〜3回)が下限に貼り付いて、大小の差が読めない図になる。
      span = Math.log(max) - Math.log(min)

      selected.map do |text, count|
        weight = span.zero? ? 1.0 : (Math.log(count) - Math.log(min)) / span
        Entry.new(text: text, count: count, weight: weight)
      end
    end
  end
end
