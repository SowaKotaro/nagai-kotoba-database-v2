max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

rails_env = ENV.fetch("RAILS_ENV") { "development" }
environment rails_env

if rails_env == "production"
  worker_count = Integer(ENV.fetch("WEB_CONCURRENCY") { 1 })
  # preload_app! が意味を持つのはワーカーを fork するクラスタモードだけで、Puma 5 以降は
  # クラスタモードなら既定で有効になる。単一モードの else で呼んでも何も起きない
  # (Puma の仕様からの判断で、起動して確かめてはいない。分岐を消すのは見送り)。
  if worker_count > 1
    workers worker_count
  else
    preload_app!
  end

  # パスの /var/www/nagai-kotoba-database は config/deploy.rb の deploy_to と同じ値の直書き。
  # deploy_to を変えるならここも直す(shared/ は Capistrano の共有ディレクトリ)。
  bind "unix:///var/www/nagai-kotoba-database/shared/tmp/sockets/puma.sock"
  pidfile "/var/www/nagai-kotoba-database/shared/tmp/pids/puma.pid"
else
  port ENV.fetch("PORT") { 3000 }
  pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }
  # Rails の puma.rb の雛形にあった行(初期コミット)。開発環境でワーカーを落とすまでの待ち時間を
  # 長くする。ただし worker_timeout はクラスタモードのワーカーにだけ効くので、ワーカーを持たない
  # 開発の単一モードでは実質何もしない(Puma の仕様からの判断で、確かめてはいない)。
  worker_timeout 3600
end

plugin :tmp_restart
