# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# コントローラは preload しない(公開ページでは使わないため。未使用 preload の警告回避)。
# data-controller が現れたときに遅延読み込みする(controllers/index.js の lazyLoad)。
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
