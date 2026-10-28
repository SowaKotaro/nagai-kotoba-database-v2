require "test_helper"

# 名前空間 Admin は Admin モデルが保持するため、テストもコンパクト形式で定義する。
# 単語の修正(一覧・1語の修正)と、一括登録の3ステップ(入力→読み→重複→登録)。解析・重複判定・登録の中身は
# BulkWordRegistrationTest、読み欄のフロント検証は AdminWordsReadingFormatTest で見る。
# 読みの自動取得(ReadingExtractor)は CI に mecab が無くても安定させるためスタブする。
class Admin::WordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(admins(:one))
    @word = words(:abc_murder)
  end

  # 表層形→読みの対応表を返すスタブ。未知の語は読み空(nil)にする。
  def stub_readings(map)
    callable = ->(surfaces) { surfaces.map { |surface| map[surface] } }
    stub_method(ReadingExtractor, :call, callable) { yield }
  end

  # --- 一覧 ---
  test "一覧: 読み・状態・件数と、修正画面/コンソールへのリンク、まとめて付ける・外すパネル" do
    get admin_words_path(q: "")
    assert_response :success
    # 公開済みの語は修正画面(注釈状態を変えずに直す)、未公開の語はコンソール(注釈して公開する)へ
    assert_select "td a[href=?]", edit_admin_word_path(@word), text: @word.surface
    assert_select ".admin-words-table__actions a[href=?]", edit_admin_word_path(@word), text: "edit."
    pending = words(:pending_haruhi)
    assert_select "td a[href=?]", admin_annotation_path(pending), text: pending.surface
    assert_select ".admin-words-table__actions a[href=?]", admin_annotation_path(pending), text: "annot."
    # 読み・注釈状態(注釈済みは日付、未注釈はラベル)
    assert_select "td.admin-words-table__reading", text: /さつじんじけん/
    assert_select ".admin-words-table__annotated", text: @word.annotated_at.strftime("%Y-%m-%d")
    assert_select ".admin-words-table__unannotated", text: "未対応", minimum: 1
    # 件数表示とページネーション
    assert_select ".admin-words-count", text: /#{Word.count}\s*語/
    assert_select ".pagination span", text: "1 / 1 ページ"

    # 一覧に、まとめて付ける・外すパネルと選択チェックボックスが 1 つのフォームで出る(Issue 37・108)
    get admin_words_path
    assert_select "form#bulk-form[action=?]", admin_bulk_annotation_path do
      # Enter での送信は、無効にした最初のボタンで止める(送り先の取り違えを防ぐ)
      assert_select "button[type=submit][disabled]:first-of-type"
      # まとめて付ける(ジャンルピッカー・チップ・特徴と該当部分・テンプレ文・注釈済みチェック)
      assert_select ".bulk-annotation", 2
      assert_select "input[type=hidden][name=?][data-genre-picker-target=value]", "bulk_annotation[genre_id]"
      assert_select "input[name=?]", "bulk_annotation[entity_type_id]"
      assert_select "input[name=?][value=?]", "bulk_annotation[linguistic_feature_id]", linguistic_features(:rendaku).id.to_s
      assert_select "input[name=?]", "bulk_annotation[feature_target]"
      assert_select "input[name=?]", "bulk_annotation[feature_target_reading]"
      assert_select "input[name=?]", "bulk_annotation[meaning_template]"
      # 注釈済みフラグは既定 OFF
      assert_select "input[name=?][checked]", "bulk_annotation[mark_annotated]", count: 0
      # まとめて外す(送信ボタンの formaction で送り先を変える)
      assert_select "input[type=hidden][name=?][data-genre-picker-target=value]", "bulk_detachment[genre_id]"
      %w[linguistic_feature_id entity_type_id part_of_speech_id].each do |key|
        assert_select "input[type=radio][name=?][value=''][checked]", "bulk_detachment[#{key}]"
      end
      assert_select "input[name=?]", "bulk_detachment[feature_target]"
      # 特徴のチップはサーバが全部を描き、選択した語に共通しないものを JS が隠す(手がかりは data-record-id)
      assert_select "[data-controller=bulk-detachment-features]" do
        assert_select "label[data-bulk-detachment-features-target=chip][data-record-id]", LinguisticFeature.count
        assert_select "p[hidden][data-bulk-detachment-features-target=status]"
      end
      assert_select "input[name=?]", "bulk_detachment[word_origin_ids][]", WordOrigin.count
      assert_select "input[type=submit][formaction=?]", admin_bulk_detachment_path
    end
    # 行のチェックボックスは form 属性で外のフォームに紐づく(2 つのパネルが共有する)。
    # data-feature-ids はその語の語義に付いた特徴の id で、特徴の無い語は空
    murder_box = css_select("tbody input[type=checkbox][name='word_ids[]'][form=bulk-form][value='#{@word.id}']").sole
    assert_equal [ linguistic_features(:rendaku).id, linguistic_features(:jubako).id ].sort,
                 murder_box["data-feature-ids"].split.map(&:to_i).sort
    assert_select "tbody input[type=checkbox][value=?][data-feature-ids='']", words(:curry).id.to_s

    # 一覧は100語ごとにページ送りする
    # コールバックを通さず一括投入(char_type_pattern は NOT NULL のため明示)
    Word.insert_all((1..110).map { |i| { surface: "ページ送り検証語#{format('%03d', i)}", char_type_pattern: "漢" } })

    get admin_words_path
    assert_select "tbody tr", count: 100
    assert_select ".pagination a", text: "次へ"

    get admin_words_path(page: 2)
    assert_select ".pagination a", text: "前へ"
    assert_select ".pagination span", text: "2 / 2 ページ"
  end

  # 特徴の絞り込みは「まとめて外す」と同じ行の選び方(WordSenseFeature.matching)。該当部分は完全一致。
  test "言語学的特徴(用語解説の順)と該当部分で絞り込め、まとめて外すパネルの初期値になる" do
    rendaku = linguistic_features(:rendaku)
    %w[ゴママヨ ハ行転呼].each { |name| LinguisticFeature.create!(name:) }

    get admin_words_path(linguistic_feature_id: rendaku.id)
    assert_select "td a", text: @word.surface
    assert_select "td a", text: words(:curry).surface, count: 0
    # 特徴の選択肢は公開側の検索と同じく用語解説の順(コンソール・デッキ・まとめて付ける/外すも Admin::AnnotationChoices で共通)
    assert_equal %w[連濁 ハ行転呼 重箱読み ゴママヨ], css_select("select#linguistic_feature_id option").drop(1).map(&:text)

    # 該当部分は特徴を選ばなくても絞れる。部分一致ではない
    get admin_words_path(feature_target: "殺")
    assert_select "p.empty-note"

    get admin_words_path(linguistic_feature_id: rendaku.id, feature_target: " 殺人 ")
    assert_select "td a", text: @word.surface
    assert_select "input[name=feature_target][value=?]", "殺人"
    # 絞り込みの条件を、まとめて外すパネルが開いた状態で引き継ぐ
    assert_select "details.bulk-annotation[open]" do
      assert_select "input[type=radio][name=?][value=?][checked]", "bulk_detachment[linguistic_feature_id]", rendaku.id.to_s
      assert_select "input[name=?][value=?]", "bulk_detachment[feature_target]", "殺人"
    end
    # 適用後に戻る一覧も、該当部分の条件を保つ
    assert_select "#bulk-form input[type=hidden][name=feature_target][value=?]", "殺人"

    get admin_words_path(linguistic_feature_id: linguistic_features(:jubako).id, feature_target: "殺人")
    assert_select "p.empty-note"
  end

  test "一覧の検索と絞り込み(表層形・読み・別表記・状態・タグ・ジャンル)は組み合わせられ、引き継がれる" do
    # 表層形の部分一致
    get admin_words_path(q: "ハルヒ")
    assert_select "td a", text: words(:pending_haruhi).surface
    assert_select "td a", text: @word.surface, count: 0
    # 読みの部分一致
    get admin_words_path(q: "さつじん")
    assert_select "td a", text: @word.surface
    # 別表記の部分一致(公開検索と条件を共有する。Issue 72)
    get admin_words_path(q: word_sense_variants(:curry_variant).surface)
    assert_select "td a", text: words(:curry).surface
    assert_select "td a", text: @word.surface, count: 0

    # 一覧を注釈状態(未対応/保留/完了)で絞り込める
    # 未対応: 保留・完了の語は出さない
    get admin_words_path(status: "annotation_pending")
    assert_select "td a", text: words(:pending_haruhi).surface
    assert_select "td a", text: @word.surface, count: 0
    assert_select "td a", text: words(:on_hold_word).surface, count: 0
    assert_select ".admin-status-tabs__tab[aria-current=page]", text: "未対応"

    # 保留: 保留の語だけ出す
    get admin_words_path(status: "annotation_on_hold")
    assert_select "td a", text: words(:on_hold_word).surface
    assert_select "td a", text: words(:pending_haruhi).surface, count: 0
    assert_select "td a", text: @word.surface, count: 0

    # 完了: 注釈済みの語だけ出す
    get admin_words_path(status: "annotation_done")
    assert_select "td a", text: @word.surface
    assert_select "td a", text: words(:pending_haruhi).surface, count: 0

    # 一覧をタグ(品詞・エンティティ・語種・ジャンル)で絞り込め、ジャンルは大分類でも配下ごと絞る
    # 品詞「名詞」: murder と curry の語義に付いている
    get admin_words_path(part_of_speech_id: parts_of_speech(:noun).id)
    assert_select "td a", text: @word.surface
    assert_select "td a", text: words(:curry).surface
    assert_select "td a", text: words(:pending_haruhi).surface, count: 0

    # エンティティ「書籍名」: murder のみ
    get admin_words_path(entity_type_id: entity_types(:book_title).id)
    assert_select "td a", text: @word.surface
    assert_select "td a", text: words(:curry).surface, count: 0

    # 語種「英語」: curry のみ
    get admin_words_path(word_origin_id: word_origins(:eigo).id)
    assert_select "td a", text: words(:curry).surface
    assert_select "td a", text: @word.surface, count: 0

    # ジャンルは小分類を直接指定しても、大分類を選んでも配下の小説に付く語が出る
    [ genres(:small_novel), genres(:large_literature) ].each do |genre|
      get admin_words_path(genre_id: genre.id)
      assert_select "td a", text: @word.surface
      assert_select "td a", text: words(:curry).surface, count: 0
    end

    # 存在しないジャンル id は0件(絞り込みは黙って外さない)
    get admin_words_path(genre_id: 999_999)
    assert_select "p.empty-note"

    # ジャンル絞り込みは大・中・小のどれを選んでも配下だけに広げる(兄弟の分類は混ぜない)
    # ジャンルを配下へ広げる処理は、管理一覧が WordSenseSearch とは別に持っている(Genre#self_and_descendant_ids)。
    # 独立した 大 → 中 2 つ → 小 3 つ の木で、いまの結果を集合ごと固定する。未公開の語も出る。
    large = Genre.create!(level: :large, name: "法律")
    medium_labor = Genre.create!(level: :medium, name: "労働法", parent: large)
    medium_civil = Genre.create!(level: :medium, name: "民法", parent: large)
    small_cases = Genre.create!(level: :small, name: "判例", parent: medium_labor)
    small_rules = Genre.create!(level: :small, name: "規則", parent: medium_labor)
    small_family = Genre.create!(level: :small, name: "家族法", parent: medium_civil)

    surfaces = {
      cases: [ "残業手当不払い請求事件", small_cases, true ], rules: [ "就業規則の不利益変更", small_rules, true ],
      family: [ "親権者変更の申立て事件", small_family, true ], draft: [ "未公開の判例の見本", small_cases, false ]
    }.transform_values do |surface, genre, published|
      word = Word.new(surface: surface)
      word.word_senses.build(reading: "ミホンノヨミ", genre: genre)
      word.mark_annotated if published
      word.save!
      word.surface
    end
    listed = lambda do |genre|
      get admin_words_path(genre_id: genre.id)
      css_select("td a").map(&:text).map(&:strip) & surfaces.values
    end

    assert_equal surfaces.values_at(:cases, :rules, :family, :draft).sort, listed.(large).sort
    assert_equal surfaces.values_at(:cases, :rules, :draft).sort, listed.(medium_labor).sort
    assert_equal surfaces.values_at(:family).sort, listed.(medium_civil).sort
    assert_equal surfaces.values_at(:cases, :draft).sort, listed.(small_cases).sort

    # タグ絞り込みは検索・注釈状態と組み合わせられる(AND)
    # 品詞「名詞」× 表層形「カレー」→ curry のみ
    get admin_words_path(part_of_speech_id: parts_of_speech(:noun).id, q: "カレー")
    assert_select "td a", text: words(:curry).surface
    assert_select "td a", text: @word.surface, count: 0

    # 品詞「名詞」× 未対応 → 0件(名詞が付く語はどちらも注釈済み)
    get admin_words_path(part_of_speech_id: parts_of_speech(:noun).id, status: "annotation_pending")
    assert_select "p.empty-note"

    # タグ絞り込みは状態タブ・一括適用フォーム・セレクトに引き継がれる
    pos_id = parts_of_speech(:noun).id
    get admin_words_path(part_of_speech_id: pos_id)

    # 状態タブのリンクが条件を保持する
    assert_select ".admin-status-tabs__tab[href*=?]", "part_of_speech_id=#{pos_id}", count: 4
    # 一括適用フォームの hidden で適用後も条件を保つ
    assert_select "#bulk-form input[type=hidden][name=part_of_speech_id][value=?]", pos_id.to_s
    # セレクトは選択状態を復元し、解除リンクが出る
    assert_select "select[name=part_of_speech_id] option[selected][value=?]", pos_id.to_s
    assert_select ".admin-words-tag-filter__reset"
  end

  # --- step2: 読みの取得 ---
  test "一括登録 step2: 読みを取得し、調査 JSON を突き合わせる(空・壊れた入力も扱う)" do
    readings = { "天上天下唯我独尊" => "テンジョウテンゲユイガドクソン" }

    stub_readings(readings) do
      post readings_admin_words_path, params: {
        bulk_word_registration: { text: "1. 天上天下唯我独尊" }
      }
    end

    assert_response :success
    assert_select "ol.steps li.is-current .steps__label", text: "読み"
    assert_select "input.bulk-review__reading-input[value=?]", "テンジョウテンゲユイガドクソン"
    # bullet(1.)は表層形から取り除かれている
    assert_select "input[name=?][value=?]", "bulk_word_registration[entries][][surface]", "天上天下唯我独尊"
    # step2 では重複警告は出さない
    assert_select "tr.bulk-review__row--warn", false

    # テキストが空だと読み取得は 422 を返す
    post readings_admin_words_path, params: { bulk_word_registration: { text: "" } }
    assert_response :unprocessable_content
    assert_select "p.form-alert"

    # 調査 JSON を反映すると不一致行に候補チップと不一致バッジが出る
    json = {
      version: "1",
      words: [ { input: "花は桜木人は武士", surface: "花は桜木人は武士",
                 reading: "ハナハサクラギヒトハブシ", confidence: "high" } ]
    }.to_json

    post apply_research_admin_words_path, params: {
      bulk_word_registration: {
        entries: [ { surface: "花は桜木人は武士", reading: "ハナハサクラギジンハブシ" } ],
        research_json: json
      }
    }

    assert_response :success
    assert_select ".reading-status--differ"
    assert_select ".reading-choice[data-reading=?]", "ハナハサクラギヒトハブシ"
    # 不一致は既定で調査側(ヒト)を採用する
    assert_select "input.bulk-review__reading-input[value=?]", "ハナハサクラギヒトハブシ"

    # 壊れた調査 JSON は警告を出し MeCab の読みを保つ
    post apply_research_admin_words_path, params: {
      bulk_word_registration: {
        entries: [ { surface: "猫", reading: "ネコ" } ],
        research_json: "{ 壊れた"
      }
    }

    assert_response :success
    assert_select "p.form-alert"
    assert_select "input.bulk-review__reading-input[value=?]", "ネコ"
  end

  # step2 フォームは formaction で duplicates と apply_research の2つに送るため、グローバル CSRF
  # トークンを埋める(per-form トークンだと apply_research 側で弾かれる)。CSRF を実際に有効化して確認。
  test "readings フォームのトークンで formaction 先(apply_research)も CSRF を通る" do
    ActionController::Base.allow_forgery_protection = true

    # step1 → step2(readings) を描画(ヘッダのログアウト等と混ざらないよう action で特定)
    get new_admin_word_path
    step1_form = css_select("form").find { |f| f["action"]&.include?("readings") }
    step1_token = step1_form.css("input[name=authenticity_token]").first["value"]
    stub_readings("資本主義" => "シホンシュギ") do
      post readings_admin_words_path, params: {
        authenticity_token: step1_token, bulk_word_registration: { text: "1. 資本主義" }
      }
    end
    assert_response :success

    # readings フォーム(action=duplicates)のトークンを取り出し、formaction 先へ送る
    form = css_select("form").find { |f| f["action"]&.include?("duplicates") }
    token = form.css("input[name=authenticity_token]").first["value"]
    post apply_research_admin_words_path, params: {
      authenticity_token: token,
      bulk_word_registration: {
        entries: [ { surface: "資本主義", reading: "シホンシュギ" } ], research_json: "{}"
      }
    }
    assert_response :success
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  # --- step3: 重複チェック(確定した読みに対して) ---
  test "一括登録 step3: 似た読みに警告し、収録基準未満はエラー表示で除外を既定にする" do
    # murder フィクスチャの読み「さつじんじけん」に一致する読みを渡す
    post duplicates_admin_words_path, params: {
      bulk_word_registration: { entries: [ { surface: "殺人事件", reading: "さつじんじけん" } ] }
    }

    assert_response :success
    assert_select "ol.steps li.is-current .steps__label", text: "重複"
    assert_select "tr.bulk-review__row--warn"
    assert_select ".bulk-review__match-reading", text: "さつじんじけん"

    # 読みが収録基準(10文字)未満の語はエラー表示し、除外に既定でチェックを入れる
    post duplicates_admin_words_path, params: {
      bulk_word_registration: { entries: [
        { surface: "資本主義", reading: "シホンシュギ" },            # 6文字: 収録基準未満
        { surface: "銀河鉄道の夜", reading: "ギンガテツドウノヨル" } # 10文字: 収録できる
      ] }
    }

    assert_response :success
    # 行ごとに除外チェックボックスがあり、基準未満の行だけ既定で除外する
    assert_select "input.bulk-review__exclude[type=checkbox]", count: 2
    assert_select "input.bulk-review__exclude[checked]", count: 1
    assert_select "tr.bulk-review__row--error", count: 1
    assert_select ".bulk-review__error-label", text: /読み 6 文字/
  end

  # --- 登録(create) ---
  test "確認後のエントリを未注釈のまままとめて登録し、除外(_exclude)にチェックした行は登録しない" do
    assert_difference [ "Word.count", "WordSense.count" ], 2 do
      post admin_words_path, params: {
        bulk_word_registration: { entries: [
          { surface: "銀河鉄道の夜", reading: "ギンガテツドウノヨル" },
          { surface: "活版印刷術", reading: "カッパンインサツジュツ" },
          { surface: "除外語", reading: "ジョガイゴ", _exclude: "1" }
        ] }
      }
    end

    assert_redirected_to admin_words_path
    word = Word.find_by(surface: "銀河鉄道の夜")
    assert_equal "ギンガテツドウノヨル", word.word_senses.sole.reading
    assert_nil word.annotated_at
    assert_not Word.exists?(surface: "除外語")
  end

  test "一括登録 step4: 読み欠落は 422、エントリが無ければ貼り付け画面へ戻す" do
    assert_no_difference -> { Word.count } do
      post admin_words_path, params: {
        bulk_word_registration: { entries: [ { surface: "読みなし語", reading: "" } ] }
      }
    end
    assert_response :unprocessable_content
    assert_select ".bulk-result__errors li"

    # エントリが無いと貼り付け画面へ戻す
    assert_no_difference -> { Word.count } do
      post admin_words_path, params: { bulk_word_registration: { entries: [] } }
    end
    assert_redirected_to new_admin_word_path
  end

  # --- 1語の修正(Issue 108) ---
  # 注釈フォームの部品はコンソールと共有する(フォームの中身は Admin::AnnotationsControllerTest で見る)。
  # ここで見るのは、コンソールと違って注釈状態・提案に触れず、来たときの一覧へ戻ること。
  test "修正画面は注釈フォームと導線を出し、未公開の語には公開はコンソールでと示す" do
    list = { q: "殺人", status: "annotation_done", page: "2" }
    get edit_admin_word_path(@word, list)
    assert_response :success
    assert_select "h1.ann-word", text: @word.surface
    assert_select "a[href=?]", word_path(@word)
    assert_select "form[action=?]", admin_word_path(@word) do
      assert_select "textarea[name=?]", "word[surface]", text: @word.surface
      assert_select "[data-nested-form-target=container] > .ann-feature", @word.primary_sense.word_sense_features.size
      list.each { |key, value| assert_select "input[type=hidden][name=?][value=?]", key.to_s, value }
      # 公開前の確認・「特徴なしで確定」はコンソールだけのもの
      assert_select "[data-controller~=publish-guard]", 0
      assert_select "input[formaction]", 0
    end
    assert_select ".ann-actionbar a[href=?]", admin_words_path(list)

    # 未公開の語の修正画面は、公開はコンソールで行うと示す
    pending = words(:pending_haruhi)
    get edit_admin_word_path(pending)
    assert_response :success
    assert_select ".ann-word-meta", text: /未公開（未対応）/
    assert_select ".ann-word-meta a[href=?]", admin_annotation_path(pending)
  end

  test "修正を保存しても注釈状態・収録日・提案は変わらず、来たときの一覧へ戻る" do
    pending = words(:pending_haruhi)
    sense = word_senses(:pending)
    list = { q: "ハルヒ", status: "annotation_pending" }

    patch admin_word_path(pending), params: list.merge(word: { word_senses_attributes: { "0" => {
      id: sense.id, reading: sense.reading, meaning: "直した意味"
    } } })

    assert_redirected_to admin_words_path(list)
    assert_equal "「#{pending.surface}」を保存しました。", flash[:notice]
    assert_equal "直した意味", sense.reload.meaning
    assert pending.reload.annotation_pending?, "修正で公開された"
    assert_nil pending.annotated_at
    assert annotation_proposals(:haruhi_proposal).reload.pending?, "修正で提案が反映済みになった"

    annotated_at = @word.annotated_at
    patch admin_word_path(@word), params: { word: { surface: "ABC殺人事件改" } }
    assert_equal [ "ABC殺人事件改", annotated_at ], [ @word.reload.surface, @word.annotated_at ]
  end

  test "保存済みの特徴を外して保存すると消え、残した特徴はそのまま残る" do
    removed, kept = word_senses(:murder).word_sense_features.order(:id).to_a
    patch admin_word_path(@word), params: { word: { word_senses_attributes: { "0" => {
      id: word_senses(:murder).id, reading: word_senses(:murder).reading,
      word_sense_features_attributes: {
        "0" => { id: removed.id, _destroy: "1" },
        "1" => { id: kept.id, linguistic_feature_id: kept.linguistic_feature_id, target: kept.target,
                 target_reading: kept.target_reading, target_start: kept.target_start }
      }
    } } } }

    assert_redirected_to admin_words_path
    assert_equal [ kept.id ], word_senses(:murder).word_sense_features.ids
  end

  test "検証に通らない修正は、入力を保ったまま修正画面に戻す" do
    patch admin_word_path(@word), params: { q: "殺人", word: { surface: "" } }
    assert_response :unprocessable_content
    assert_select ".error-explanation"
    assert_select "input[type=hidden][name=q][value=?]", "殺人"
    assert_equal "ABC殺人事件", @word.reload.surface
  end

  # --- 削除 ---
  test "単語を削除すると語義も消える" do
    word = word_senses(:murder).word

    assert_difference -> { Word.count }, -1 do
      delete admin_word_path(word)
    end
    assert_redirected_to admin_words_path
    assert_not WordSense.exists?(word_senses(:murder).id)
  end

  test "単語を削除すると、語義に付いた言語学的特徴も消える" do
    feature_ids = word_senses(:murder).word_sense_features.ids
    assert_equal 2, feature_ids.size

    delete admin_word_path(words(:abc_murder))
    assert_empty WordSenseFeature.where(id: feature_ids)
  end
end
