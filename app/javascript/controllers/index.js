// data-controller が現れたコントローラだけを遅延読み込みする(lazy)。
// そのページで使わないコントローラは読み込まないので、未使用 preload の警告も出ない
// (公開ページでも、ヘッダーの nav-drawer・nav-menu・theme は毎ページ読み込まれる)。
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
lazyLoadControllersFrom("controllers", application)
