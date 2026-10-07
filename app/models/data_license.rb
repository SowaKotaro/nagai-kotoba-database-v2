# 単語データのライセンス(CC BY 4.0。クレジットはサイト名 + URL。ja.yml の pages.about.license_credit)。
# About・JSON API(words/_license.json.jbuilder)・JSON-LD(StructuredDataHelper)が同じ値を出す。
# 画面に出す正式名は i18n の pages.about.license_name(「クリエイティブ・コモンズ 表示 4.0 国際 (CC BY 4.0)」)。
# 種別: 値オブジェクト（DB に触れない）。
module DataLicense
  SHORT_NAME = "CC BY 4.0".freeze
  URL = "https://creativecommons.org/licenses/by/4.0/deed.ja".freeze
end
