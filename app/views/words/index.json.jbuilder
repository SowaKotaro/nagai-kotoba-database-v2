# 単語一覧の公開 JSON(Issue 25)。ページネーションをそのまま反映する。
host = Rails.application.config.x.canonical_host

json.page @page
json.total_pages @total_pages
json.total_count @total_count

json.words @words do |word|
  json.id word.id
  json.surface word.surface
  json.url "#{host}#{word_path(word)}"
  json.readings word.word_senses.map(&:reading)
end

json.partial! "words/license"
