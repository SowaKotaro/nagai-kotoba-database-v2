# 公開 JSON API のライセンス表記(Issue 25)。CC BY 4.0・クレジット = サイト名 + URL。
json.license do
  json.name DataLicense::SHORT_NAME
  json.url DataLicense::URL
  json.credit I18n.t("pages.about.license_credit", url: SiteUrl.origin)
end
