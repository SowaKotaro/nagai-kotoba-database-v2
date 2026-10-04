module SearchesHelper
  # 読みの文字数スライダーの上端。ここまで動かすと「N文字以上」(上限なし)の意味になり、上限の hidden を空で送る。
  READING_LENGTH_SLIDER_MAX = 30

  # 読みの文字数スライダー(Stimulus range_slider)へ渡す値(WordRequestsHelper#reading_counter_data と同じ形)。
  # 下端は収録基準 WordSense::MIN_READING_LENGTH(これより短い語は収録しないので選ばせない)。
  # 文言は ja.yml(%{min}・%{max} は JS が差し込む)。
  def reading_length_slider_data
    {
      controller: "range-slider",
      range_slider_min_value: WordSense::MIN_READING_LENGTH,
      range_slider_max_value: READING_LENGTH_SLIDER_MAX,
      range_slider_at_least_value: t("searches.reading_length_slider.at_least"),
      range_slider_exact_value: t("searches.reading_length_slider.exact"),
      range_slider_between_value: t("searches.reading_length_slider.between")
    }
  end

  # 適用中の検索条件を [ラベル, 値の文字列] の配列で返す(結果ヘッダのチップ表示用)。
  def applied_search_conditions(search)
    conditions = []
    conditions << [ t("searches.q_label"), search.q ] if search.q.present?
    conditions << [ t("searches.regexp"), search.regexp ] if search.regexp.present?
    if search.reading_length_min || search.reading_length_max
      conditions << [ t("searches.reading_length"), reading_length_phrase(search) ]
    end
    if search.reading_length
      conditions << [ t("words.show.reading_length"), t("words.show.chars", count: search.reading_length) ]
    end
    conditions << [ t("words.show.mora_count"), t("words.show.mora", count: search.mora_count) ] if search.mora_count
    WordSenseSearch::SOUND_COUNT_FILTERS.each_key do |key|
      minimum = search.public_send(key)
      conditions << [ t("searches.sound_counts.#{key}"), t("searches.sound_counts.at_least", count: minimum) ] if minimum
    end
    conditions << [ t("searches.first_char"), search.first_char.join("・") ] if search.first_char.present?
    conditions << [ t("searches.last_char"), search.last_char.join("・") ] if search.last_char.present?
    if search.effective_genres.any?
      conditions << [ WordSense.human_attribute_name(:genre), search.effective_genres.map(&:name).join("・") ]
    end
    conditions << [ WordSense.human_attribute_name(:part_of_speech), master_names(PartOfSpeech, search.part_of_speech_id) ] if search.part_of_speech_id.present?
    conditions << [ WordSense.human_attribute_name(:entity_type), master_names(EntityType, search.entity_type_id) ] if search.entity_type_id.present?
    conditions << [ t("searches.linguistic_feature"), master_names(LinguisticFeature, search.linguistic_feature_id) ] if search.linguistic_feature_id.present?
    conditions << [ t("words.show.origins"), master_names(WordOrigin, search.word_origin_id) ] if search.word_origin_id.present?
    conditions << [ t("searches.vowel_pattern"), search.vowel_reading ] if search.vowel_reading.present?
    conditions << [ t("searches.vowel_transition"), vowel_transition_phrase(search) ] if search.vowel_transition.present?
    conditions << [ WordSense.human_attribute_name(:rhythm_pattern), search.rhythm_pattern ] if search.rhythm_pattern.present?
    conditions << [ t("words.show.char_type_pattern"), char_type_pattern_phrase(search) ] if search.char_type_pattern.present?
    conditions
  end

  private

  # 母音の遷移の条件チップ。「3〜5拍目: オ段 → ウ段 → イ段」と、拍位置つきで読ませる。
  def vowel_transition_phrase(search)
    position, pattern = search.vowel_transition_path
    t("searches.vowel_transition_value",
      from: position, to: position + pattern.length - 1,
      rows: pattern.each_char.map { |vowel| t("vowel_rows.#{vowel}") }.join(" → "))
  end

  def reading_length_phrase(search)
    min = search.reading_length_min
    max = search.reading_length_max
    if min && max && min == max then t("words.show.chars", count: min)
    elsif max.nil? then t("searches.length_at_least", count: min)
    elsif min.nil? then t("searches.length_at_most", count: max)
    else t("searches.length_between", min: min, max: max)
    end
  end

  # 文字種の条件チップ表示。パターンに一致方法・大小区別を添える。
  def char_type_pattern_phrase(search)
    detail = [ t("searches.char_type_match_#{search.char_type_partial? ? 'partial' : 'exact'}"),
               t("searches.char_type_case_#{search.char_type_case_sensitive? ? 'sensitive' : 'insensitive'}") ].join("・")
    "#{search.char_type_pattern}（#{detail}）"
  end

  def master_names(model, ids)
    model.where(id: ids).order(:name).pluck(:name).join("・")
  end
end
