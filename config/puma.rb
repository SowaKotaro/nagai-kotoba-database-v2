max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

rails_env = ENV.fetch("RAILS_ENV") { "development" }
environment rails_env

if rails_env == "production"
  worker_count = Integer(ENV.fetch("WEB_CONCURRENCY") { 1 })
  if worker_count > 1
    workers worker_count
  else
    preload_app!
  end

  bind "unix:///var/www/nagai-kotoba-database/shared/tmp/sockets/puma.sock"
  pidfile "/var/www/nagai-kotoba-database/shared/tmp/pids/puma.pid"
else
  port ENV.fetch("PORT") { 3000 }
  pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }
  worker_timeout 3600
end

plugin :tmp_restart