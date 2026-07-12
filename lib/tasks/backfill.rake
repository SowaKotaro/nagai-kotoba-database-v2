# 既存レコードへ、後から追加した派生カラムの値を埋め直すためのタスク。
# 冪等(何度実行しても同じ結果)。マイグレーションで追加した mora_count / vowel_pattern は
# NULL 許容のため、既存行は本タスクで backfill する。
# update_all や直接 SQL で reading / surface を更新すると派生カラムが古くなるため、
# その修復にも本タスクを使う(事前の検出は backfill:verify)。
namespace :backfill do
  desc "既存の語義に reading 由来の派生値(rhythm_pattern/vowel_pattern/mora_count/last_char)を再生成する"
  task reading_metrics: :environment do
    updated = 0
    WordSense.find_each do |sense|
      rhythm = RhythmPattern.call(sense.reading)
      sense.update_columns(
        rhythm_pattern: rhythm,
        vowel_pattern: VowelPattern.call(rhythm),
        mora_count: MoraCount.call(sense.reading),
        last_char: LastChar.call(sense.reading)
      )
      updated += 1
    end
    puts "reading 由来の派生値を再生成しました: #{updated} 件"
  end

  desc "Ruby 側派生カラムの現在値と再計算値の差分を報告する(読み取り専用)"
  task verify: :environment do
    # reading_length / first_char は SQL の STORED 生成カラムのため常に整合し、対象外。
    mismatches = 0

    Word.find_each do |word|
      expected = CharTypePattern.call(word.surface)
      next if word.char_type_pattern == expected

      mismatches += 1
      puts "words##{word.id} char_type_pattern: #{word.char_type_pattern.inspect} → #{expected.inspect}"
    end

    WordSense.find_each do |sense|
      rhythm = RhythmPattern.call(sense.reading)
      {
        rhythm_pattern: rhythm,
        vowel_pattern: VowelPattern.call(rhythm),
        mora_count: MoraCount.call(sense.reading),
        last_char: LastChar.call(sense.reading)
      }.each do |column, expected|
        actual = sense[column]
        next if actual == expected

        mismatches += 1
        puts "word_senses##{sense.id} #{column}: #{actual.inspect} → #{expected.inspect}"
      end
    end

    if mismatches.zero?
      puts "派生カラムの不整合はありません"
    else
      puts "不整合: #{mismatches} 件。word_senses の修復は bin/rails backfill:reading_metrics、" \
           "words.char_type_pattern の修復は該当 Word の保存(before_validation で再導出)で行う"
    end
  end
end
