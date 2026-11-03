require "test_helper"

class SearchWayMenusTest < ActiveSupport::TestCase
  # 公開語はフィクスチャの ABC殺人事件(小説・書籍名・名詞・漢語・連濁と重箱読み・7 字)と カレーライス(名詞・英語・3 字)。
  # 未注釈の 涼宮ハルヒの憂鬱 / バミューダトライアングル は選択肢に数えない。
  test "選択肢は公開語義のあるものだけを並べ、単語一覧の絞り込みの値を持つ" do
    # フィクスチャの読みは 10 字に満たないので、10 字・17 字・25 字の公開語を足す。人名と英語の数もここで増やす
    create_published_word(surface: "見本その一", reading: "アイウエオカキクケコ",
                          entity_type: entity_types(:person_name), word_origin_ids: [ word_origins(:eigo).id ])
    create_published_word(surface: "見本その二", reading: "アイウエオカキクケコサシスセソタチ", entity_type: entity_types(:person_name))
    create_published_word(surface: "見本その三", reading: "アイウエオカキクケコサシスセソタチツテトナニヌネノ")

    menus = SearchWayMenus.all
    assert_equal SearchWayMenus::KEYS, menus.keys
    ids = ->(key, param) { menus[key].map { |option| option.params[param] } }

    # 大分類は、公開語義のある小分類から辿ったものだけ
    assert_equal [ [ genres(:large_literature).name, { genre_id: genres(:large_literature).id } ] ], menus[:genre].map(&:to_a)
    # エンティティと語種は語の多い順(人名 2 → 書籍名 1、英語 2 → 漢語 1)、品詞は登録順、言語学的特徴は用語解説の順
    assert_equal [ entity_types(:person_name).id, entity_types(:book_title).id ], ids.(:entity_type, :entity_type_id)
    assert_equal [ word_origins(:eigo).id, word_origins(:kango).id ], ids.(:word_origin, :word_origin_id)
    assert_equal [ parts_of_speech(:noun).id ], ids.(:part_of_speech, :part_of_speech_id)
    assert_equal [ linguistic_features(:rendaku).id, linguistic_features(:jubako).id ], ids.(:linguistic_feature, :linguistic_feature_id)

    # 読みの長さは語のある区切りだけ。19 文字までは 1 文字ずつちょうどの値で、20 文字以上はまとめて下限だけで絞る
    assert_equal [ [ 10..10, { reading_length: 10 } ],
                   [ 17..17, { reading_length: 17 } ],
                   [ 20.., { reading_length_min: 20 } ] ], menus[:reading_length].map(&:to_a)

    # ホームは毎リクエスト読むので、組んだ選択肢はキャッシュから返し、マスタを引き直さない
    with_rails_cache do
      SearchWayMenus.all
      assert_no_queries { assert_equal menus, SearchWayMenus.all }
    end
  end
end
