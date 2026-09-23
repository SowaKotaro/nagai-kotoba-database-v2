require "test_helper"

# notation の段: 書き出し → 結果の取り込み → 取り込み済みの語を done へ → done のリストをコピー。
class Admin::Candidates::NotationsControllerTest < ActionDispatch::IntegrationTest
  test "結果を取り込んで done へ送ると、一括登録に貼るリストに出る" do
    sign_in_as(admins(:one))
    candidate = WordCandidate.create!(surface: "ゴールドマンサックス", status: :notation)
    waiting = WordCandidate.create!(surface: "まだの言葉", status: :notation)

    get admin_candidates_notation_path
    assert_select "textarea[name=notation_input]", text: "##{candidate.id} ゴールドマンサックス\n##{waiting.id} まだの言葉"

    post import_admin_candidates_notation_path,
         params: { json: { words: [ { id: candidate.id, surface: "ゴールドマン・サックス", entry_score: 5 } ] }.to_json }
    assert_redirected_to admin_candidates_notation_path

    patch admin_candidates_notation_path
    assert_redirected_to admin_candidates_notation_path(anchor: "done")
    assert_predicate candidate.reload, :done?
    assert_predicate waiting.reload, :notation?

    follow_redirect!
    assert_select "textarea[name=done_list]", text: "ゴールドマン・サックス"
  end

  test "done の語は一括登録で収録されると登録済みになる" do
    sign_in_as(admins(:one))
    candidate = WordCandidate.create!(surface: "新しく登録する言葉", status: :done)

    post admin_words_path, params: { bulk_word_registration: { entries: [ { surface: candidate.surface, reading: "アタラシクトウロクスルコトバ" } ] } }

    candidate.reload
    assert_predicate candidate, :registered?
    assert_equal Word.find_by!(surface: "新しく登録する言葉"), candidate.word
  end
end
