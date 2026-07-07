# 言語学的特徴の用語解説(config/linguistic_features_glossary.yml)の読み出し専用モデル(Issue 39)。
# マスタ(linguistic_features)は name のみの単純マスタのまま、説明文はコード管理の YAML に置く
# (マイグレーション不要・変更をレビューできる)。アノテーション・コンソールの「用語解説」
# パネルと docs/annotation-guidelines.md §6 が参照する。
class LinguisticFeatureGlossary
  Entry = Struct.new(:name, :description, :examples, keyword_init: true)

  GLOSSARY_PATH = "config/linguistic_features_glossary.yml".freeze

  class << self
    def all
      @all ||= load_entries
    end

    def find(name)
      index[name]
    end

    private

    def index
      @index ||= all.index_by(&:name)
    end

    def load_entries
      data = YAML.load_file(Rails.root.join(GLOSSARY_PATH))
      data.fetch("features").map do |feature|
        Entry.new(
          name: feature.fetch("name"),
          description: feature.fetch("description"),
          examples: Array(feature["examples"])
        )
      end
    end
  end
end
