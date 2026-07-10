# 品詞(parts_of_speech)マスタを冪等に投入する。
# 日本語(学校文法)の自立語・付属語に、本アプリが扱う実務的な区分
# (固有名詞・数詞・接辞・連語)を加えたもの。
# 単純マスタ(name + UNIQUE)。必要に応じて管理者が追加できる。
# 冪等: find_or_create_by! なので再実行しても重複しない。
PARTS_OF_SPEECH = [
  "普通名詞",
  "固有名詞",
  "連語"
].freeze

PARTS_OF_SPEECH.each do |name|
  PartOfSpeech.find_or_create_by!(name: name)
end

puts "品詞マスタを投入しました: #{PartOfSpeech.count} 件"
