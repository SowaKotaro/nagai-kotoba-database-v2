# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# 品詞(PartOfSpeech)のテーブル名を parts_of_speech に対応させる。
# 既定の複数形は part_of_speeches になってしまうため、不規則変化として登録する。
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "part_of_speech", "parts_of_speech"
end
