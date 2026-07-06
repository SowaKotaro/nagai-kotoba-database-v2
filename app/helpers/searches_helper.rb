module SearchesHelper
  # 先頭/末尾文字の 50音表(カタカナ・濁音/半濁音含む)。読みはカタカナ基準。
  # 1列 = 1行(ア行・カ行…)を上から下(ア段→オ段)に並べる。nil は段を揃える空セル。
  KANA_COLUMNS = [
    %w[ア イ ウ エ オ],
    [ nil, nil, "ヴ", nil, nil ],
    %w[カ キ ク ケ コ],
    %w[ガ ギ グ ゲ ゴ],
    %w[サ シ ス セ ソ],
    %w[ザ ジ ズ ゼ ゾ],
    %w[タ チ ツ テ ト],
    %w[ダ ヂ ヅ デ ド],
    %w[ナ ニ ヌ ネ ノ],
    %w[ハ ヒ フ ヘ ホ],
    %w[バ ビ ブ ベ ボ],
    %w[パ ピ プ ペ ポ],
    %w[マ ミ ム メ モ],
    [ "ヤ", nil, "ユ", nil, "ヨ" ],
    %w[ラ リ ル レ ロ],
    [ "ワ", "ヰ", nil, "ヱ", "ヲ" ],
    [ "ン", nil, nil, nil, nil ]
  ].freeze

  # 適用中の検索条件を [ラベル, 値の文字列] の配列で返す(結果ヘッダのチップ表示用)。
  def applied_search_conditions(search)
    conditions = []
    conditions << [ t("searches.q_label"), search.q ] if search.q.present?
    if search.reading_length_min || search.reading_length_max
      conditions << [ t("searches.reading_length"), reading_length_phrase(search) ]
    end
    if search.reading_length
      conditions << [ t("words.show.reading_length"), t("words.show.chars", count: search.reading_length) ]
    end
    conditions << [ t("words.show.mora_count"), t("words.show.mora", count: search.mora_count) ] if search.mora_count
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
    conditions << [ WordSense.human_attribute_name(:rhythm_pattern), search.rhythm_pattern ] if search.rhythm_pattern.present?
    conditions << [ t("words.show.char_type_pattern"), search.char_type_pattern ] if search.char_type_pattern.present?
    conditions
  end

  private

  def reading_length_phrase(search)
    min = search.reading_length_min
    max = search.reading_length_max
    if min && max && min == max then t("words.show.chars", count: min)
    elsif max.nil? then t("searches.length_at_least", count: min)
    elsif min.nil? then t("searches.length_at_most", count: max)
    else t("searches.length_between", min: min, max: max)
    end
  end

  def master_names(model, ids)
    model.where(id: ids).order(:name).pluck(:name).join("・")
  end
end
