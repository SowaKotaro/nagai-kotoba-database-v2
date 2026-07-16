# マスタ seed の名前カタログ(単一の正)。db/seeds.rb と管理画面(タグ統括管理)の両方から参照する。
# エンティティタイプと小分類ジャンルは seed 管理ではなく、管理画面から自由に追加する。
#
# 運用ルール(Issue 49: deploy:seed × リネームの重複再発防止):
#   /admin/tags で seed 管理のマスタ(タグ管理画面で「seed」印のもの)をリネーム/統合したら、
#   本ファイルも必ず更新する。更新しないままデプロイすると、deploy:seed が旧名のマスタを
#   再作成してしまう(2026-07-10 に本番で重複が発生した既知の事故)。
#   - リネーム: 名前リストを新名に書き換え、RENAMES に 旧名 => 新名 を追記する。
#     seed 実行時に旧名のレコードを新名へ改名するため、他環境(開発・新規構築)も自動で追従する。
#   - 統合(名前の廃止): 名前リストから削除する(残すと次回デプロイで復活する)。
#   - RENAMES の適用時、移行先の名前が既に存在する場合は改名せずスキップして警告を出す
#     (データが付いている可能性があるため、機械的に統合はしない。/admin/tags で統合する)。
class SeedCatalog
  # ==== ジャンル(大分類・中分類) ====================================================
  # 出典: docs/genres.md(日本十進分類法を基にした独自階層)。
  # 小分類(level3)はここでは登録しない(アノテーション運用の中で管理画面から追加する)。
  # 分類コード列は持たない方針のため、名前＋親子関係のみで管理する。
  # 大分類 => その配下の中分類(表示順)。
  GENRES = {
    "知識総合・情報整理・メタ構造" => [
      "知識論・学問論",
      "方法論・推論・形式体系",
      "記号体系・表現形式",
      "知識構造化・分類体系",
      "文献学・アーカイブ論",
      "メディア理論・コミュニケーション",
      "知識編集・統合・調整"
    ],
    "哲学・宗教・心理" => [
      "哲学総論",
      "論理学・哲学主題",
      "地域・文化圏思想",
      "時代別思想",
      "宗教総論",
      "宗派・教義",
      "心理学・行動科学",
      "倫理学・価値論"
    ],
    "歴史・地理" => [
      "歴史総論",
      "日本史",
      "アジア史・東洋史",
      "ヨーロッパ史・西洋史",
      "アフリカ史",
      "北アメリカ史・中央アメリカ史",
      "南アメリカ史",
      "オセアニア史",
      "北極・南極地方史",
      "哲学史・宗教史",
      "社会史・経済史",
      "医学史・薬学史",
      "科学史・技術史",
      "美術史・文学史",
      "文化史・生活史",
      "地理総論",
      "人文地理学",
      "自然地理学",
      "地誌学",
      "人類学・考古学"
    ],
    "社会・経済" => [
      "社会科学総論",
      "政治",
      "法律",
      "経済・金融",
      "財政",
      "統計",
      "社会・労働・福祉",
      "教育",
      "風俗習慣・民俗学・民族学",
      "国防・軍事"
    ],
    "自然科学" => [
      "自然科学総論",
      "数学",
      "物理学",
      "化学",
      "天文学・宇宙科学",
      "地球科学・地学",
      "生物科学・一般生物学",
      "植物学",
      "動物学",
      "獣医学",
      "医学",
      "薬学",
      "歯学"
    ],
    "技術・工業・家庭" => [
      "技術・工学総論",
      "建築工学・土木工学",
      "建築学",
      "機械工学",
      "物理工学",
      "電気工学・電子工学",
      "情報工学",
      "海洋工学・船舶工学",
      "兵器・軍事工学",
      "金属工学・鉱山工学",
      "化学工業",
      "製造工業",
      "家政学・生活科学総論",
      "家政・生活技術",
      "生活システム"
    ],
    "産業・商業" => [
      "産業総論",
      "農業",
      "園芸・造園",
      "蚕糸業",
      "畜産業",
      "林業・狩猟",
      "水産業",
      "商業総論",
      "広告・マーケティング",
      "貿易",
      "運輸・交通",
      "サービス業",
      "郵便",
      "放送・電気通信"
    ],
    "芸術・音楽・演劇・スポーツ・娯楽" => [
      "芸術・美術総論",
      "彫刻・オブジェ",
      "絵画技法",
      "絵画様式",
      "書・書道",
      "デザイン",
      "版画・篆刻",
      "写真・印刷",
      "工芸・家具・人形",
      "音楽総論",
      "音楽理論・技法",
      "楽器・合奏",
      "伝統音楽",
      "現代音楽",
      "演劇総論",
      "演劇理論・演出・舞台技術",
      "伝統芸能",
      "現代舞台芸術・舞踊",
      "大衆演芸",
      "映画・ドラマ・アニメーション",
      "芸能・エンタメ",
      "スポーツ総論",
      "フィジカルスポーツ",
      "メンタルスポーツ",
      "武道・武術・格闘技",
      "諸芸・芸道総論",
      "諸芸・芸道",
      "娯楽総論",
      "テーブルゲーム・パーティーゲーム",
      "射倖ゲーム・ギャンブル",
      "デジタルゲーム",
      "レジャー・アクティビティ",
      "視聴覚メディア"
    ],
    "言語" => [
      "言語総論",
      "文字論",
      "音韻論",
      "語源論・意味論",
      "語彙論",
      "統語論",
      "文体論・談話分析",
      "形態論",
      "語用論",
      "方言学",
      "成句論・句構造分析",
      "応用言語論・言語計画",
      "歴史言語学",
      "社会言語学",
      "心理言語学",
      "計算言語学"
    ],
    "文書・出版物" => [
      "文書・出版物総論",
      "小説・エッセイ・物語",
      "詩歌",
      "戯曲・脚本",
      "古典文学",
      "漫画・コミック",
      "絵本・児童書",
      "雑誌・逐次刊行物（カレンダー含む）",
      "図像資料・視覚出版物",
      "地図・地理情報出版物",
      "実用書",
      "ビジネス書",
      "専門書",
      "資格試験本・辞書・学習参考書",
      "ノンフィクション・記録出版物"
    ]
  }.freeze

  # ジャンルのリネーム追従マップ。キーは「大分類名」または「大分類名/中分類名」のパス、値は新名。
  # 親も同時に改名する場合は、親(大分類)のリネームを先に書き、中分類のパスは改名後の親名で書く。
  # ※ 名前に「/」を含むジャンルには使えない(現状存在しない)。
  GENRE_RENAMES = {}.freeze

  # ==== 語種 ========================================================================
  # 「外来語」で束ねず言語ごとに切り分ける方針。混種語は語義に複数の語種を紐づけて
  # 表現するため、ここには単一の語源としての値のみを並べる(開いた集合)。
  WORD_ORIGINS = [
    "日本語",
    "中国語",
    "韓国語",
    "英語",
    "フランス語",
    "ドイツ語",
    "イタリア語",
    "スペイン語",
    "ポルトガル語",
    "ロシア語",
    "ギリシャ語",
    "ラテン語",
    "サンスクリット語"
  ].freeze

  WORD_ORIGIN_RENAMES = {}.freeze # 旧名 => 新名

  # ==== 品詞 ========================================================================
  # 実務的な最小構成。必要に応じて管理者が追加できる(動詞・形容詞などは管理画面から追加済み)。
  PARTS_OF_SPEECH = [
    "普通名詞",
    "固有名詞",
    "連語"
  ].freeze

  PART_OF_SPEECH_RENAMES = {}.freeze # 旧名 => 新名

  # ==== 言語学的特徴 ================================================================
  # 読み・表記に関わる現象を、単語の「該当部分」ごとに付与するためのタグ。
  # 方針: 傘語(音便 など)は置かず、具体的な種類(葉)だけを並べる。
  #   ― 音便は4種に分ける。オノマトペは擬音語/擬態語の2種とし、上位語が認知されやすいため
  #     ラベルに「オノマトペ(...)」を残す(この項目だけの例外)。
  # 特徴を追加したら用語解説(config/linguistic_feature_glossary.yml)も更新すること。
  LINGUISTIC_FEATURES = [
    # --- 読みの変化(連濁系) ---
    "連濁",        # 例: 硫黄島(いおうジマ) ― 後部要素の頭が濁音になる
    "半濁音化",    # 例: 出発(しゅっパツ) ― 後部要素の頭が半濁音になる
    "連声",        # 例: 反応(ハンノウ)、三位(サンミ) ― 前音の末尾が後音の頭に影響する
    "音韻添加",    # 例: 真中(まんなか) ― 音韻が加わる
    "音韻脱落",    # 例: 河原(かわら) ― 音韻が落ちる
    "転音",        # 例: 雨(あめ)→雨傘(あまがさ) ― 母音の交替(被覆形/露出形)
    "促音化",      # 例: 活(かつ)→活版(かっぱん) ― 前部要素の末尾が促音に変わる
    # --- 漢字の読みの当て方 ---
    "熟字訓",      # 例: 硫黄(いおう)、五月雨(さみだれ) ― 熟語全体に訓読みを当てる
    "重箱読み",    # 例: 台所(ダイどころ) ― 前が音読み・後が訓読み
    "湯桶読み",    # 例: 手本(てホン) ― 前が訓読み・後が音読み
    "当て字",      # 例: 目出度い(めでたい) ― 意味に関係なく漢字を当てる
    "古式読み",    # 例: 中臣鎌足(なかとみのかまたり) ― 古い読み方を残す
    "特殊読み",    # 例: 青眼の白龍(ブルーアイズホワイトドラゴン) ― 特殊な当て読み
    # --- 音便(4種) ---
    "促音便",      # 例: 立ちて→立って
    "撥音便",      # 例: 飛びて→飛んで
    "イ音便",      # 例: 書きて→書いて
    "ウ音便",      # 例: ありがたく→ありがとう
    # --- 語形成 ---
    "畳語",        # 例: 人々、時々 ― 同じ語基の繰り返し
    # --- オノマトペ(2種: 擬声語は擬音語に、擬容語・擬情語は擬態語に含める) ---
    "オノマトペ（擬音語）",   # 例: わんわん、ざあざあ、がちゃん ― 声や物音
    "オノマトペ（擬態語）",   # 例: きらきら、うろうろ、いらいら ― 状態・様子・心情
    # --- 言葉遊び ---
    "ゴママヨ"
  ].freeze

  LINGUISTIC_FEATURE_RENAMES = {}.freeze # 旧名 => 新名

  class << self
    # 全マスタを冪等に投入する(db/seeds.rb から呼ぶ)。
    def seed_all!
      apply_genres!(tree: GENRES, renames: GENRE_RENAMES)
      puts "ジャンルを投入しました: 大分類#{Genre.large.count}件 / 中分類#{Genre.medium.count}件"

      apply_simple!(WordOrigin, names: WORD_ORIGINS, renames: WORD_ORIGIN_RENAMES)
      puts "語種マスタを投入しました: #{WordOrigin.count} 件"

      apply_simple!(PartOfSpeech, names: PARTS_OF_SPEECH, renames: PART_OF_SPEECH_RENAMES)
      puts "品詞マスタを投入しました: #{PartOfSpeech.count} 件"

      apply_simple!(LinguisticFeature, names: LINGUISTIC_FEATURES, renames: LINGUISTIC_FEATURE_RENAMES)
      puts "言語学的特徴マスタを投入しました: #{LinguisticFeature.count} 件"
    end

    # 単純マスタ(name のみ)への投入。リネーム追従 → 不足分の作成、の順で冪等に適用する。
    def apply_simple!(model, names:, renames: {})
      renames.each do |old_name, new_name|
        record = model.find_by(name: old_name)
        next unless record

        if model.exists?(name: new_name)
          puts "  ⚠ #{model.name}:「#{old_name}」→「#{new_name}」は移行先が既に存在するため" \
               "改名をスキップしました(/admin/tags で統合してください)"
        else
          record.update!(name: new_name)
          puts "  #{model.name}:「#{old_name}」を「#{new_name}」に改名しました"
        end
      end

      names.each { |name| model.find_or_create_by!(name: name) }
    end

    # ジャンル(大・中の2階層)への投入。リネーム追従 → 木の不足分の作成、の順で冪等に適用する。
    def apply_genres!(tree:, renames: {})
      ActiveRecord::Base.transaction do
        renames.each { |old_path, new_name| rename_genre(old_path, new_name) }

        tree.each do |large_name, medium_names|
          large = Genre.find_or_create_by!(parent_id: nil, name: large_name) do |g|
            g.level = :large
          end

          medium_names.each do |medium_name|
            large.children.find_or_create_by!(name: medium_name) do |g|
              g.level = :medium
            end
          end
        end
      end
    end

    # レコードが seed 管理(本カタログ収載)かどうか。タグ統括管理の「seed」印・警告表示に使う。
    # genre_index は id => Genre の索引(一覧表示での親参照の N+1 回避用。省略時は record.parent を辿る)。
    def seeded?(kind_key, record, genre_index: nil)
      case kind_key
      when "genres"
        seeded_genre?(record, genre_index)
      when "word_origins"
        WORD_ORIGINS.include?(record.name)
      when "parts_of_speech"
        PARTS_OF_SPEECH.include?(record.name)
      when "linguistic_features"
        LINGUISTIC_FEATURES.include?(record.name)
      else
        false
      end
    end

    # この種別に seed 管理のレコードが含まれうるか(一覧の注記表示に使う)。
    def kind_seeded?(kind_key)
      %w[genres word_origins parts_of_speech linguistic_features].include?(kind_key)
    end

    private

    def seeded_genre?(genre, genre_index)
      case genre.level
      when "large"
        GENRES.key?(genre.name)
      when "medium"
        parent = genre_index ? genre_index[genre.parent_id] : genre.parent
        GENRES.fetch(parent&.name, []).include?(genre.name)
      else
        false # 小分類は seed 管理しない
      end
    end

    def rename_genre(old_path, new_name)
      *parent_names, old_name = old_path.split("/")
      scope =
        if parent_names.empty?
          Genre.large
        else
          parent = Genre.large.find_by(name: parent_names.first)
          return unless parent

          parent.children
        end

      record = scope.find_by(name: old_name)
      return unless record

      if Genre.exists?(parent_id: record.parent_id, name: new_name)
        puts "  ⚠ Genre:「#{old_path}」→「#{new_name}」は移行先が既に存在するため" \
             "改名をスキップしました(/admin/tags で統合してください)"
      else
        record.update!(name: new_name)
        puts "  Genre:「#{old_path}」を「#{new_name}」に改名しました"
      end
    end
  end
end
