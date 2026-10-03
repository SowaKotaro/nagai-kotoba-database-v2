# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# コントローラは preload しない。28 本を全ページで modulepreload すると、そのページで使わない
# ものに未使用 preload の警告が出るため、data-controller が現れたものだけを遅延読み込みする
# (controllers/index.js の lazyLoad)。公開ページでも、ヘッダーの 3 本(nav-drawer・nav-menu・theme)は
# 毎ページ読み込まれる。
pin_all_from "app/javascript/controllers", under: "controllers", preload: false

# Plotly(vendor/javascript/plotly.min.js。v2.35.2・約 4.5MB)は意図してピンしない。UMD で
# window.Plotly を定義する作りなので、ES module として読むと動かない。統計ページの
# genre_sunburst_controller だけが <script> で差し込み、配信は Sprockets(app/assets/config/manifest.js の
# vendor/javascript の link_tree)に頼る。ピンしないので bin/importmap audit の対象外になる。
# 更新するときは、ファイル先頭の版を確かめ、plotly.js の既知の脆弱性を自分で調べる。
