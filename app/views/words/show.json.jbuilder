# 単語詳細の公開 JSON(Issue 25)。読み取り専用・注釈済みのみ(HTML と共通)。
host = Rails.application.config.x.canonical_host

json.id @word.id
json.surface @word.surface
json.url "#{host}#{word_path(@word)}"
json.char_type_pattern @word.char_type_pattern

json.senses @word.word_senses do |sense|
  json.reading sense.reading
  json.meaning sense.meaning
  json.reading_length sense.reading_length
  json.mora_count sense.mora_count
  json.first_char sense.first_char
  json.last_char sense.last_char
  json.rhythm_pattern sense.rhythm_pattern
  json.vowel_pattern sense.vowel_pattern

  if sense.genre
    json.genre sense.genre.self_and_ancestors do |genre|
      json.id genre.id
      json.name genre.name
      json.level genre.level
    end
  else
    json.genre nil
  end

  json.part_of_speech sense.part_of_speech&.name
  json.entity_type sense.entity_type&.name
  json.word_origins sense.word_origins.map(&:name)

  json.linguistic_features sense.word_sense_features do |feature|
    json.name feature.linguistic_feature.name
    json.target feature.target
    json.target_reading feature.target_reading
  end

  json.variants sense.word_sense_variants do |variant|
    json.surface variant.surface
    json.reading variant.reading
  end
end

json.partial! "words/license"
