# 既存レコードへ、後から追加した派生カラムの値を埋め直すためのタスク。
# 冪等(何度実行しても同じ結果)。マイグレーションで追加した mora_count / vowel_pattern は
# NULL 許容のため、既存行は本タスクで backfill する。
namespace :backfill do
  desc "既存の語義に reading 由来の派生値(rhythm_pattern/vowel_pattern/mora_count)を再生成する"
  task reading_metrics: :environment do
    updated = 0
    WordSense.find_each do |sense|
      rhythm = RhythmPattern.call(sense.reading)
      sense.update_columns(
        rhythm_pattern: rhythm,
        vowel_pattern: VowelPattern.call(rhythm),
        mora_count: MoraCount.call(sense.reading)
      )
      updated += 1
    end
    puts "reading 由来の派生値を再生成しました: #{updated} 件"
  end
end
