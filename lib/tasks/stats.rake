# 統計ページ §1「級数見本」の形態素頻度を事前集計する(Issue 78)。
#
# 本番・CI には MeCab が無いため、集計は MeCab のあるローカルで行い、
# 結果(db/morpheme_frequencies.json)をコミットして本番は読むだけにする。
# 冪等: 何度実行しても同じ入力からは同じ結果になる(backfill:reading_metrics と同じ作法)。
#
# 使い方:
#   bin/rails stats:morphemes                      # 公開済みの語(DB)から集計する
#   bin/rails stats:morphemes SURFACES_FILE=path   # 1行1語のファイルから集計する
#
# SURFACES_FILE は、手元の DB が本番と同期していないときの逃げ道。
# 本番の公開データは https://nagai-kotoba-database.jp/llms-full.txt から取れるので、
# そこから見出し語を抜いたファイルを渡せば本番相当の集計ができる。
namespace :stats do
  desc "統計ページの級数見本用に、収録語の形態素頻度を集計して db/morpheme_frequencies.json を更新する"
  task morphemes: :environment do
    extractor = MorphemeExtractor.new
    unless extractor.available?
      abort "mecab が見つかりません。この集計は MeCab のある環境(ローカル)で実行してください。"
    end

    surfaces = load_surfaces
    if surfaces.empty?
      abort "集計対象の語がありません。"
    end

    puts "#{surfaces.size} 語を解析します..."
    counts = Hash.new(0)
    # 一度に渡しすぎるとプロセスの入出力が膨らむので小分けにする。
    surfaces.each_slice(500) do |batch|
      extractor.call(batch).each do |morphemes|
        # 同じ語の中に同じ部品が2回出ても「その語に現れた」の1回として数える
        # (「時々」のような畳語で頻度が二重に乗るのを避ける)。
        morphemes.uniq.each { |morpheme| counts[morpheme] += 1 if morpheme.length >= 2 }
      end
      print "."
    end
    puts

    metadata = MorphemeFrequencies.write!(counts, word_count: surfaces.size)
    puts "書き出しました: #{MorphemeFrequencies::PATH}"
    puts "  対象語数: #{metadata['word_count']} / 形態素の種類: #{metadata['morpheme_count']}"
    puts "  見本に載る形態素(#{MorphemeFrequencies::MIN_COUNT}回以上): #{MorphemeFrequencies.entries.size}"
    puts "  上位10件:"
    MorphemeFrequencies.entries.first(10).each do |entry|
      puts "    #{entry.count.to_s.rjust(4)}  #{entry.text}"
    end
  end

  def load_surfaces
    path = ENV["SURFACES_FILE"].presence
    if path
      abort "ファイルが見つかりません: #{path}" unless File.exist?(path)
      File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)
    else
      Word.annotated.order(:id).pluck(:surface)
    end
  end
end
