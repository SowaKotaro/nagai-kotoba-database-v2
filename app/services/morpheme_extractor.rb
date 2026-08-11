# 表層形を形態素(名詞)へ分割するサービス。統計ページ §1「級数見本」の事前集計で使う。
# MeCab の CLI を Open3 で呼び出す(gem は増やさない方針。ReadingExtractor と同じ作法)。
#
# ReadingExtractor との違いが2つある。
#
# 1. **辞書は既定(ipadic)を使い、neologd は使わない**。
#    neologd は固有名詞に強く、読みの取得には最適だが、「涼宮ハルヒの憂鬱」を丸ごと1語として
#    持っているため、部品を数えたいこの用途では何も分割されない。級数見本が見たいのは
#    「選手権」「症候群」のような繰り返し現れる部品なので、既定辞書の方が目的に合う。
#
# 2. **連続するカタカナの名詞は1語に畳む**。既定辞書は長いカタカナ語を知らないことが多く、
#    「シャーロット」を「シャー」+「ロット」のように誤って割ってしまう(本番データでは
#    ワンピースのシャーロット家22件がこれに当たり、集計の1位2位を占めていた)。
#    カタカナの連続は元の表層形では地続きなので、畳んで1語として数える方が実態に合う。
#
# 退避: mecab 未インストール/失敗時は例外を握りつぶして空配列を返す(集計タスクが警告を出す)。
class MorphemeExtractor
  require "open3"

  KATAKANA_ONLY = /\A[ァ-ヶー]+\z/
  NOUN = "名詞".freeze

  # 数えても見どころにならない語(数詞・非自立・代名詞など)は落とす。
  SKIPPED_NOUN_SUBTYPES = %w[数 非自立 代名詞 接尾 接続詞的 動詞非自立的].freeze

  def self.call(surfaces)
    new.call(surfaces)
  end

  # 表層形の配列を受け取り、入力と同じ並びで「形態素(名詞)の配列」の配列を返す。
  # 1回のプロセス起動でまとめて解析する(1件ずつ起動しない)。
  def call(surfaces)
    surfaces = Array(surfaces)
    return [] if surfaces.empty?
    return Array.new(surfaces.size) { [] } unless available?

    output, status = Open3.capture2(*command, stdin_data: mecab_input(surfaces))
    return Array.new(surfaces.size) { [] } unless status.success?

    parse(output, surfaces.size)
  rescue Errno::ENOENT, IOError, SystemCallError
    Array.new(surfaces.size) { [] }
  end

  def available?
    Open3.capture2("mecab", "--version")
    true
  rescue Errno::ENOENT, SystemCallError
    false
  end

  private

  # 辞書は指定しない = システム既定(ipadic)を使う。neologd を明示的に避けるのが要点。
  def command = [ "mecab" ]

  # 改行が語の区切りなので、表層形に混ざった改行は空白へ寄せる。
  def mecab_input(surfaces)
    surfaces.map { |surface| surface.to_s.gsub(/[\r\n]+/, " ") }.join("\n") + "\n"
  end

  # MeCab の出力(1形態素1行・入力1行ごとに EOS)を、入力と同じ並びの配列へ組み直す。
  def parse(output, expected_size)
    results = []
    current = []
    katakana_run = []

    flush = lambda do
      current << katakana_run.join if katakana_run.any?
      katakana_run = []
    end

    output.each_line do |line|
      line = line.chomp
      if line == "EOS"
        flush.call
        results << current
        current = []
        next
      end

      surface, feature = line.split("\t", 2)
      unless keep?(surface, feature)
        flush.call
        next
      end

      if surface.match?(KATAKANA_ONLY)
        katakana_run << surface
      else
        flush.call
        current << surface
      end
    end
    flush.call
    results << current if current.any?

    # 想定件数に満たない/超える場合も並びを崩さないよう長さを合わせる。
    results.fill([], results.size...expected_size) if results.size < expected_size
    results.first(expected_size)
  end

  def keep?(surface, feature)
    return false if surface.nil? || surface.empty? || feature.nil?

    fields = feature.split(",")
    return false unless fields.first == NOUN

    SKIPPED_NOUN_SUBTYPES.exclude?(fields[1])
  end
end
