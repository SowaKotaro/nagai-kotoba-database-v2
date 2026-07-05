# 表層形(漢字かな交じり)から読み(カタカナ)を自動取得するサービス。
# MeCab の CLI(`mecab -Oyomi`)を Open3 で呼び出す。gem(natto 等)は増やさない方針。
#
# セキュリティ: 引数は配列で渡し(シェルを経由しない)、入力は標準入力から渡すため、
#   表層形にどんな文字が含まれてもコマンドインジェクションは起こらない。
#
# 辞書: 既定は mecab-ipadic-neologd(固有名詞・新語に強い)。
#   環境変数 MECAB_DICT でパスを上書きできる。辞書が見つからなければ既定辞書へフォールバックする。
#
# 退避: mecab 未インストール/失敗時は例外を握りつぶし、全件 nil(読み空)を返す。
#   → 画面側で管理者が手入力できる(機能を止めない)。
class ReadingExtractor
  require "open3"

  # neologd の一般的なインストール先。環境変数が無いときの既定値。
  DEFAULT_NEOLOGD_PATHS = [
    "/usr/lib/x86_64-linux-gnu/mecab/dic/mecab-ipadic-neologd",
    "/usr/local/lib/mecab/dic/mecab-ipadic-neologd",
    "/var/lib/mecab/dic/mecab-ipadic-neologd"
  ].freeze

  # 複数の表層形をまとめて渡し、入力と同じ並びの読み(カタカナ or nil)配列を返す。
  # 1回のプロセス起動でまとめて解析する(1件ずつ起動しない)。
  def self.call(surfaces)
    new.call(surfaces)
  end

  def call(surfaces)
    surfaces = Array(surfaces)
    return [] if surfaces.empty?
    return Array.new(surfaces.size) unless mecab_available?

    output, status = Open3.capture2(*command, stdin_data: surfaces.join("\n"))
    return Array.new(surfaces.size) unless status.success?

    # -Oyomi は入力1行につき読み1行を出力する。並びを入力に合わせて対応付ける。
    readings = output.split("\n").map { |line| normalize(line) }
    surfaces.each_index.map { |i| readings[i] }
  rescue StandardError
    # mecab 不在・辞書エラー等は握りつぶし、手入力に委ねる。
    Array.new(surfaces.size)
  end

  private

  # 実行コマンド(配列)。辞書があれば -d で指定する。
  def command
    cmd = [ "mecab", "-Oyomi" ]
    dict = dict_path
    cmd += [ "-d", dict ] if dict
    cmd
  end

  def dict_path
    env = ENV["MECAB_DICT"].presence
    return env if env && Dir.exist?(env)

    DEFAULT_NEOLOGD_PATHS.find { |path| Dir.exist?(path) }
  end

  def mecab_available?
    return @mecab_available if defined?(@mecab_available)

    @mecab_available = system("mecab", "--version", out: File::NULL, err: File::NULL) || false
  end

  def normalize(line)
    reading = line.to_s.strip
    reading.presence
  end
end
