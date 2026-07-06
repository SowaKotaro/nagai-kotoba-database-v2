# 公開 JSON API のライセンス表記(Issue 25)。CC BY 4.0・クレジット = サイト名 + URL。
json.license do
  json.name "CC BY 4.0"
  json.url "https://creativecommons.org/licenses/by/4.0/deed.ja"
  json.credit I18n.t("pages.about.license_credit", url: Rails.application.config.x.canonical_host)
end
