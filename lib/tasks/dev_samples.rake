# デザイン・動作確認用のダミーデータを投入する開発環境専用タスク。
# 冪等(何度実行しても重複しない)。seeds には含めない(本番の deploy:seed に載せないため)。
namespace :dev do
  desc "デザイン確認用のダミーデータを投入する(開発環境専用)"
  task sample_data: :environment do
    abort "開発環境専用のタスクです(RAILS_ENV=#{Rails.env})" unless Rails.env.development?

    # --- マスタ ---
    noun = PartOfSpeech.find_or_create_by!(name: "名詞")
    proper_noun = PartOfSpeech.find_or_create_by!(name: "固有名詞")
    phrase = PartOfSpeech.find_or_create_by!(name: "連語")

    book = EntityType.find_or_create_by!(name: "書籍名")
    station = EntityType.find_or_create_by!(name: "駅名")
    system_name = EntityType.find_or_create_by!(name: "制度名")

    rendaku = LinguisticFeature.find_or_create_by!(name: "連濁")
    LinguisticFeature.find_or_create_by!(name: "熟字訓")
    jubako = LinguisticFeature.find_or_create_by!(name: "重箱読み")
    yuto = LinguisticFeature.find_or_create_by!(name: "湯桶読み")

    # 既存の中分類(パターンで検索)の下に小分類を用意する。見つからなければ genre なしで登録する。
    small_genre = lambda do |medium_pattern, name|
      medium = Genre.medium.where("name LIKE ?", "%#{medium_pattern}%").first
      next nil unless medium

      Genre.create_with(level: :small).find_or_create_by!(parent: medium, name: name)
    end

    literature = small_genre.call("文学", "近代小説")
    energy = small_genre.call("エネルギー", "電力・エネルギー制度") || small_genre.call("電気", "電力・エネルギー制度")
    zoology = small_genre.call("生物", "動物学")
    food = small_genre.call("食", "食文化")
    season = small_genre.call("気象", "気象・季節") || small_genre.call("地球", "気象・季節")
    railway = small_genre.call("鉄道", "鉄道・駅") || small_genre.call("交通", "鉄道・駅")
    language = small_genre.call("言語", "語彙・言葉遊び") || small_genre.call("日本語", "語彙・言葉遊び")
    economy = small_genre.call("経済", "企業・経営")
    architecture = small_genre.call("建築", "和風建築")

    # --- 単語(語義・特徴つき) ---
    # features: [特徴, 該当部分(表層の一部), その読み(語義の読みの一部)]
    entries = [
      { surface: "再生可能エネルギー賦課金",
        senses: [ { reading: "サイセイカノウエネルギーフカキン", genre: energy, pos: noun, entity: system_name,
                    meaning: "再生可能エネルギーの普及のため、電気料金に上乗せして徴収される負担金。" } ] },
      { surface: "吾輩は猫である",
        senses: [ { reading: "ワガハイハネコデアル", genre: literature, pos: phrase, entity: book,
                    meaning: "夏目漱石の長編小説。猫の視点から人間社会を風刺する。",
                    features: [ [ yuto, "吾輩", "ワガハイ" ] ] } ] },
      { surface: "銀河鉄道の夜",
        senses: [ { reading: "ギンガテツドウノヨル", genre: literature, pos: phrase, entity: book,
                    meaning: "宮沢賢治の童話。ジョバンニとカムパネルラの幻想的な旅を描く。" } ] },
      { surface: "ABC殺人事件",
        senses: [ { reading: "エービーシーサツジンジケン", genre: literature, pos: noun, entity: book,
                    meaning: "アガサ・クリスティの長編推理小説。アルファベット順の連続殺人を扱う。" } ] },
      { surface: "高輪ゲートウェイ",
        senses: [ { reading: "タカナワゲートウェイ", genre: railway, pos: proper_noun, entity: station,
                    meaning: "JR山手線・京浜東北線の駅。2020年開業。" } ] },
      { surface: "生物",
        senses: [ { reading: "セイブツ", genre: zoology, pos: noun,
                    meaning: "生命をもつものの総称。動物・植物・微生物など。" },
                  { reading: "ナマモノ", genre: food, pos: noun,
                    meaning: "加熱していない食品。刺身など生の食べ物。" } ] },
      { surface: "小春日和",
        senses: [ { reading: "コハルビヨリ", genre: season, pos: noun,
                    meaning: "晩秋から初冬にかけての、穏やかで暖かな晴天。",
                    features: [ [ rendaku, "日和", "ビヨリ" ] ] } ] },
      { surface: "三日月",
        senses: [ { reading: "ミカヅキ", genre: season, pos: noun,
                    meaning: "新月から3日目ごろに見える細い月。",
                    features: [ [ rendaku, "月", "ヅキ" ] ] } ] },
      { surface: "雪見障子",
        senses: [ { reading: "ユキミショウジ", genre: architecture, pos: noun,
                    meaning: "下部にガラスをはめ、閉めたまま雪景色を眺められる障子。",
                    features: [ [ yuto, "雪見障子", "ユキミショウジ" ] ] } ] },
      { surface: "株式会社",
        senses: [ { reading: "カブシキガイシャ", genre: economy, pos: noun,
                    meaning: "株式を発行して資金を集め、株主の出資で運営される会社形態。",
                    features: [ [ rendaku, "会社", "ガイシャ" ] ] } ] },
      { surface: "一石二鳥",
        senses: [ { reading: "イッセキニチョウ", genre: language, pos: noun,
                    meaning: "1つの行為で2つの利益を得ること。" } ] },
      { surface: "春一番",
        senses: [ { reading: "ハルイチバン", genre: season, pos: noun,
                    meaning: "立春から春分の間に、その年初めて吹く強い南風。",
                    features: [ [ jubako, "春一番", "ハルイチバン" ] ] } ] }
    ]

    created_words = 0
    created_senses = 0

    ActiveRecord::Base.transaction do
      entries.each do |entry|
        word = Word.find_or_create_by!(surface: entry[:surface]) { created_words += 1 }

        entry[:senses].each do |attrs|
          sense = word.word_senses.find_or_create_by!(reading: attrs[:reading]) do |s|
            s.genre = attrs[:genre]
            s.part_of_speech = attrs[:pos]
            s.entity_type = attrs[:entity]
            s.meaning = attrs[:meaning]
            created_senses += 1
          end

          Array(attrs[:features]).each do |feature, target, target_reading|
            sense.word_sense_features.find_or_create_by!(linguistic_feature: feature, target: target) do |f|
              f.target_reading = target_reading
            end
          end
        end
      end
    end

    puts "投入完了: words=#{Word.count} senses=#{WordSense.count} features=#{WordSenseFeature.count}" \
         " (新規 words+#{created_words} senses+#{created_senses})"
  end
end
