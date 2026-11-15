# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# コントローラは preload しない。すべてを全ページで modulepreload すると、そのページで使わない
# ものに未使用 preload の警告が出るため、data-controller が現れたものだけを遅延読み込みする
# (controllers/index.js の lazyLoad)。公開ページでも、ヘッダーの 4 本(nav-drawer・nav-menu・theme・header-reveal)は
# 毎ページ読み込まれる。
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
