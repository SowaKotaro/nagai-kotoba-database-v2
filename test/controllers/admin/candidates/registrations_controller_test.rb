require "test_helper"

# 登録待ち: /reading 用に書き出し、一括登録の読みの確認(step2)へそのまま渡す。収録されると登録済みになる。
class Admin::Candidates::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "登録待ちの語を一括登録の読みの確認へ渡し、収録されると登録済みになる" do
    sign_in_as(admins(:one))
    candidate = WordCandidate.create!(surface: "新しく登録する言葉", status: :ready)

    get admin_candidates_registration_path
    assert_response :success
    assert_select "textarea[name=reading_export]", text: "新しく登録する言葉"
    assert_select "form[action=?][data-turbo=false] input[name='bulk_word_registration[text]'][value=?]",
                  readings_admin_words_path, "新しく登録する言葉"

    post admin_words_path, params: { bulk_word_registration: { entries: [ { surface: candidate.surface, reading: "アタラシクトウロクスルコトバ" } ] } }

    candidate.reload
    assert_predicate candidate, :registered?
    assert_equal Word.find_by!(surface: "新しく登録する言葉"), candidate.word
  end
end
