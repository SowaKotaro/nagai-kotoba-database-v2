# アノテーション調査用データの書き出し(Issue 38)。
# 対象語(word_id・表層形・読み)とマスタ一覧(ジャンル木・エンティティ・品詞・語種・
# 言語学的特徴)をまとめた JSON を作る。この JSON を word-annotation-research スキルへ
# 渡すと、語ごとの提案 JSON(取り込み画面に貼る形式)が返ってくる。
class AnnotationResearchExport
  VERSION = "2".freeze

  def initialize(words)
    @words = words
  end

  def as_json
    {
      "version" => VERSION,
      "words" => word_entries,
      "masters" => masters
    }
  end

  def to_json(*)
    JSON.pretty_generate(as_json)
  end

  private

  def word_entries
    @words.map do |word|
      {
        "word_id" => word.id,
        "surface" => word.surface,
        "reading" => word.word_senses.map(&:reading).uniq.join("、")
      }
    end
  end

  # マスタ一覧(選択肢)の組み立ては1語の再調査(ReannotationExport)と共通。
  def masters
    AnnotationMasters.as_json
  end
end
