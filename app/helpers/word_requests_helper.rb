module WordRequestsHelper
  # 読みの字数カウンタ(Stimulus reading_counter)へ渡す値。
  # 収録基準の数値は WordSense::MIN_READING_LENGTH を単一の正とし、文言は ja.yml から取る。
  def reading_counter_data
    min = WordSense::MIN_READING_LENGTH
    {
      controller: "reading-counter",
      reading_counter_min_value: min,
      reading_counter_unit_value: t("word_requests.reading_counter.unit"),
      reading_counter_satisfied_value: t("word_requests.reading_counter.satisfied", min: min),
      reading_counter_short_value: t("word_requests.reading_counter.short", min: min)
    }
  end
end
