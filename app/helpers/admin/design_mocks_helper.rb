# デザイン案モック(Admin::DesignMocksController)専用の固定データ。
# DB に接続しないモックなので、表示する語・統計はすべてここに直書きする。
# 値は実データから抜いたもの(2026-07 時点)で、雰囲気の比較に足りる分だけ持つ。
module Admin::DesignMocksHelper
  # 各案の識別子 → 表示名と一行説明。URL の :style もこのキーに限る。
  STYLES = {
    "measure" => { name: "計測室", tagline: "純白と方眼、蛍光イエロー。長さを目盛りで測る" },
    "broadside" => { name: "大版面", tagline: "極太ゴシックの巨大版面。文字の物量で見せる" },
    "risograph" => { name: "二色刷り", tagline: "マゼンタ×シアンの版ズレ。可笑しみを怒鳴らせる" },
    "neobrutalism" => { name: "ネオブルータリズム", tagline: "黒の太枠とぼかさない影、原色のベタ" },
    "swiss" => { name: "スイススタイル", tagline: "グリッドと赤黒。図形を多めに使った国際様式" },
    "refined" => { name: "活字見本帖 改", tagline: "現行デザインのまま、余白の精度と Wikipedia 的な情報整理を足す" }
  }.freeze

  # 各案で作るページ。URL の :page もこのキーに限る。
  PAGES = {
    "home" => "トップページ",
    "word" => "単語詳細",
    "ranking" => "ランキング"
  }.freeze

  MockWord = Data.define(:surface, :reading, :length, :genre, :crossing)

  # 一覧・ランキングに使う語(読みの文字数の多い順)。
  def mock_words
    [
      MockWord.new("殺す時間を殺すための時間", "コロスジカンヲコロスタメノジカン", 16, "現代小説", 9),
      MockWord.new("天上天下唯我独尊", "テンジョウテンゲユイガドクソン", 15, "原始仏教", 47),
      MockWord.new("栴檀は双葉より芳し", "センダンハフタバヨリカンバシ", 14, "成句", 12),
      MockWord.new("好きこそ物の上手なれ", "スキコソモノノジョウズナレ", 13, "成句", 15),
      MockWord.new("ピーターパンシンドローム", "ピーターパンシンドローム", 12, "通俗心理学", 7),
      MockWord.new("バミューダトライアングル", "バミューダトライアングル", 12, "海洋・海域", 3),
      MockWord.new("ボストン茶会事件", "ボストンチャカイジケン", 11, "アメリカ独立革命", 11),
      MockWord.new("風が強く吹いている", "カゼガツヨクフイテイル", 11, "現代小説", 8),
      MockWord.new("エルニーニョ現象", "エルニーニョゲンショウ", 11, "気象学", 9),
      MockWord.new("活版印刷術", "カッパンインサツジュツ", 11, "印刷技術史", 5),
      MockWord.new("メソポタミア文明", "メソポタミアブンメイ", 10, "古代文明", 6)
    ]
  end

  # 円環交差数の多い順(トップ)。
  def mock_crossing_ranking
    mock_words.sort_by { |word| -word.crossing }.take(6)
  end

  # 読みの文字数ごとの収録数。10〜15 で横ばい、16 で崖になるのが実データの形。
  def mock_distribution
    [ [ 10, 292 ], [ 11, 299 ], [ 12, 278 ], [ 13, 291 ], [ 14, 270 ], [ 15, 280 ], [ 16, 6 ] ]
  end

  # 単語詳細ページの見本。
  def mock_detail
    {
      surface: "殺す時間を殺すための時間",
      reading: "コロスジカンヲコロスタメノジカン",
      length: 16,
      crossing: 9,
      romaji: "korosujikanokorosutamenojikan",
      char_types: "漢あ漢漢あ漢ああああ漢漢",
      genres: %w[作品 文学 現代小説],
      part_of_speech: "名詞",
      origin: "和語＋漢語",
      features: [ "同語反復", "格助詞「を」を含む", "サ行変格活用を含む" ],
      meaning: "ピン芸人・どくさいスイッチ企画による超短編集。2024年にKADOKAWAから刊行された。",
      published: "2024年",
      summary: "読み16文字の日本語。収録語のうち最長の6語に入る。同じ語（時間・殺す）を二度繰り返す構造が長さの理由になっている。",
      updated_on: "2026年7月18日"
    }
  end

  # 要約ボックス(Wikipedia の infobox 相当)。ラベルと値だけを持ち、並び順もここで決める。
  def mock_infobox
    detail = mock_detail
    [
      [ "読み", detail[:reading] ],
      [ "読みの文字数", "#{detail[:length]} 字" ],
      [ "分類", detail[:genres].join(" › ") ],
      [ "品詞", detail[:part_of_speech] ],
      [ "語種", detail[:origin] ],
      [ "円環交差数", "#{detail[:crossing]} 回" ],
      [ "初出", detail[:published] ]
    ]
  end

  # ページ内の目次(Notion / Wikipedia の TOC 相当)。
  def mock_toc
    [
      [ "meaning", "意味" ],
      [ "data", "言語データ" ],
      [ "related", "関連する語" ],
      [ "source", "出典・更新" ]
    ]
  end

  # 「言語データ」節に置く key-value。infobox より細かい値を入れる。
  def mock_properties
    detail = mock_detail
    [
      [ "表層形", detail[:surface] ],
      [ "読み（カタカナ）", detail[:reading] ],
      [ "ローマ字", detail[:romaji] ],
      [ "字種列", detail[:char_types] ],
      [ "読みの文字数", "#{detail[:length]} 字" ],
      [ "先頭・末尾の字", "コ ／ ン" ],
      [ "円環交差数", "#{detail[:crossing]} 回" ],
      [ "語義の数", "1 件" ]
    ]
  end

  # 「関連する語」節。関連の理由ごとにまとめる(相互リンクの密度を作るため)。
  def mock_related_groups
    [
      { label: "同じジャンル（現代小説）", words: mock_words.values_at(7, 3) },
      { label: "同じ長さ（16字）", words: [ mock_words[1] ] },
      { label: "同じ字種列（漢＋ひらがな）", words: mock_words.values_at(2, 3) }
    ]
  end

  # 収録全体の統計。
  def mock_stats
    { words: "1,760", senses: "1,762", average: "12.6", max: "16" }
  end

  # トップに置く「入口」の整理。何ができるサイトなのかを3つに畳む。
  def mock_entry_points
    [
      { title: "五十音・文字数から引く", desc: "読みの頭文字と長さで、収録語を索引のように辿ります。", meta: "索引" },
      { title: "条件を重ねて絞る", desc: "ジャンル・語種・品詞・言語的特徴を組み合わせて検索します。", meta: "詳細検索" },
      { title: "長さと音の並びで見る", desc: "読みの長さ順、円環交差数順など、数値で並べ替えます。", meta: "ランキング" }
    ]
  end

  # ランキングページで選べる並び順。
  def mock_ranking_kinds
    [
      { key: "length_desc", label: "読みが長い順", unit: "字", note: "読みの文字数。10字未満は収録対象外。" },
      { key: "length_asc", label: "読みが短い順", unit: "字", note: "収録下限の10字に並ぶ語。" },
      { key: "crossing_desc", label: "円環交差数が多い順", unit: "回", note: "五十音を円環に並べ、読みの順に線で結んだときの交差回数。" },
      { key: "crossing_asc", label: "円環交差数が少ない順", unit: "回", note: "音が近い順に並んでいる語ほど小さくなる。" }
    ]
  end

  # モックの隣の案・隣のページへ移るための一覧(切替バー用)。
  def mock_style_links
    STYLES.map { |key, meta| [ key, meta[:name] ] }
  end
end
