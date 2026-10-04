//= link_tree ../images
//= link_directory ../stylesheets .css
//= link_tree ../../javascript .js
// vendor/javascript の link_tree は Plotly(plotly.min.js)の配信に要る。Plotly は importmap に
// 意図してピンせず、統計ページが asset_path で <script> を差し込む(config/importmap.rb の注記)。
//= link_tree ../../../vendor/javascript .js
