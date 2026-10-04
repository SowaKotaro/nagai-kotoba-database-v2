# Ruby 側で作る派生値を、既存レコードについて作り直すためのタスク。冪等(何度実行しても同じ結果)。
# いまの主な用途は修復: update_all や直接 SQL で reading / surface を書き換えると、コールバックを
# 通らないので派生値が古くなる。backfill:verify で差分を検出し、reading_metrics(語義の読み由来の値と、
# それを集計した words の代表値)で直す。words の代表値だけなら sense_metrics。
# 派生カラムを新しく足したときの埋め直しにも使う。どの派生値をどれで直すかの一覧は docs/data-model.md §3。
namespace :backfill do
  desc "既存の語義に reading 由来の派生値(WordSense.reading_derivations)を再生成し、words の代表値も焼き直す"
  task reading_metrics: :environment do
    updated = 0
    WordSense.find_each do |sense|
      sense.update_columns(WordSense.reading_derivations(sense.reading))
      updated += 1
    end
    # update_columns はコールバック(after_commit の代表値の焼き直し)を通らないので、ここで全件焼き直す。
    # 焼き直しは words.updated_at を進めないので、詳細ページの ETag や sitemap の版は動かない。
    WordSenseMetrics.refresh!
    puts "reading 由来の派生値を再生成しました: #{updated} 件(words の代表値も焼き直しました)"
  end

  desc "words のランキング指標(語義の代表値)を全件焼き直す"
  task sense_metrics: :environment do
    # 通常は word_senses / 別表記 / 特徴の after_commit(RefreshesWordMetrics)が
    # 自動で追従する。update_all や直接 SQL で語義をいじった後の修復に使う。
    WordSenseMetrics.refresh!
    puts "words のランキング指標を焼き直しました: #{Word.count} 件"
  end

  desc "Ruby 側派生カラムと words の代表値の、現在値と再計算値の差分を報告する(読み取り専用)"
  task verify: :environment do
    # reading_length / first_char / surface_length は SQL の STORED 生成カラムのため常に整合し、対象外。
    # words.reading_density も STORED だが max_reading_length(代表値)から作るので、代表値の突き合わせで見る。
    mismatches = 0

    Word.find_each do |word|
      expected = CharTypePattern.call(word.surface)
      next if word.char_type_pattern == expected

      mismatches += 1
      puts "words##{word.id} char_type_pattern: #{word.char_type_pattern.inspect} → #{expected.inspect}"
    end

    WordSense.find_each do |sense|
      WordSense.reading_derivations(sense.reading).each do |column, expected|
        actual = sense[column]
        next if actual == expected

        mismatches += 1
        puts "word_senses##{sense.id} #{column}: #{actual.inspect} → #{expected.inspect}"
      end
    end

    # words の代表値(語義側の集計)。焼き直しと同じ式で突き合わせる(WordSenseMetrics::COLUMN_EXPRESSIONS)。
    WordSenseMetrics.mismatches.each do |mismatch|
      mismatches += 1
      puts "words##{mismatch[:word_id]} #{mismatch[:column]}: #{mismatch[:actual].inspect} → #{mismatch[:expected].inspect}"
    end

    if mismatches.zero?
      puts "派生カラムの不整合はありません"
    else
      puts "不整合: #{mismatches} 件。word_senses の修復は bin/rails backfill:reading_metrics(words の代表値も焼き直す)、" \
           "words の代表値だけなら bin/rails backfill:sense_metrics、" \
           "words.char_type_pattern の修復は該当 Word の保存(before_validation で再導出)で行う"
    end
  end
end
