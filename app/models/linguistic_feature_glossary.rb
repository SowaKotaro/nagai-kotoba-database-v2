# 言語学的特徴の用語解説(config/linguistic_features_glossary.yml)の読み出し専用モデル(Issue 39)。
# マスタ(linguistic_features)は name のみの単純マスタのまま、説明文はコード管理の YAML に置く
# (マイグレーション不要・変更をレビューできる)。アノテーション・コンソールの「用語解説」
# パネルと docs/annotation-guidelines.md §7 が参照する。
# 種別: 値オブジェクト（DB に触れない）。
class LinguisticFeatureGlossary
  Entry = Struct.new(:name, :description, :examples, keyword_init: true) do
    # 説明の最初の 1 文(句点まで)。説明は「定義 → 起こらない場合・このデータベースで付ける範囲」の順に書くので、
    # 探す画面(/linguistic_features)で定義だけを短く見せるのに使う。句点が無ければ説明の全文。
    def definition = description[/\A[^。]*。/] || description
  end

  GLOSSARY_PATH = "config/linguistic_features_glossary.yml".freeze

  class << self
    # プロセス内のメモで、再起動まで保持する(YAML を直したら Puma を再起動して読み直す)。
    def all
      @all ||= load_entries
    end

    def find(name)
      index[name]
    end

    # YAML での並び(0 始まり)。用語解説に無い名前は nil。
    def position(name)
      positions[name]
    end

    private

    def index
      @index ||= all.index_by(&:name)
    end

    def positions
      @positions ||= all.each_with_index.to_h { |entry, i| [ entry.name, i ] }
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
