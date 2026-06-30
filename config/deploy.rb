# config valid for current version and patch releases of Capistrano
lock "~> 3.20.1"

set :application, "nagai-kotoba-database"
set :repo_url, "git@github.com:SowaKotaro/nagai-kotoba-database-v2.git"
set :branch, "main"

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, "/var/www/nagai-kotoba-database"
set :rbenv_type, :user
set :rbenv_ruby, File.read(".ruby-version").strip

set :linked_files, %w[config/database.yml config/master.key]
set :linked_dirs, %w[log tmp/pids tmp/cache tmp/sockets storage]

set :keep_releases, 5
set :puma_systemctl_user, :user
# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
# append :linked_files, "config/database.yml", 'config/master.key'

# Default value for linked_dirs is []
# append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system", "vendor", "storage"

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5

# Uncomment the following to require manually verifying the host key before first deploy.
# set :ssh_options, verify_host_key: :secure
#
set :ssh_options, {
  keys: %w[~/.ssh/nagai_kotoba_database_deploy],
  forward_agent: false,
  auth_methods: %w[publickey]
}
set :default_env, {
  "NAGAI_KOTOBA_DATABASE_V2_PASSWORD" => ENV["NAGAI_KOTOBA_DATABASE_V2_PASSWORD"]
}

namespace :deploy do
  desc "管理者(seed)を作成/更新する。credentials の admin: を読み込む。seed は冪等なので毎回実行して安全。"
  task :seed do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env, "production") do
          execute :bundle, :exec, :rails, "db:seed"
        end
      end
    end
  end

  # マイグレーション完了後に seed を自動実行する。
  after "deploy:migrate", "deploy:seed"
end
