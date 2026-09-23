# 調査スキル(Claude Code)の出力 JSON を、管理画面の貼り付け欄から読むための共通処理。
# チャットやエディタからのコピーで付いてくる ```json フェンスを剥がしてからパースする。
module ResearchJson
  module_function

  # 前後の空白と ```json フェンスを剥がす。
  def strip_code_fence(json_text)
    json_text.to_s.strip.sub(/\A```(?:json)?\s*\n/, "").sub(/\n?```\z/, "")
  end

  # トップレベルのオブジェクトから key の配列を取り出す。形が違う・パースできないときは nil。
  def array_at(json_text, key)
    parsed = JSON.parse(strip_code_fence(json_text))
    list = parsed.is_a?(Hash) ? parsed[key] : nil
    list.is_a?(Array) ? list.select { |item| item.is_a?(Hash) } : nil
  rescue JSON::ParserError
    nil
  end
end
