// data-controller が現れたコントローラだけを遅延読み込みする(lazy)。
// 公開ページ(コントローラ不要)では JS を読み込まず、未使用 preload の警告も出ない。
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
lazyLoadControllersFrom("controllers", application)
