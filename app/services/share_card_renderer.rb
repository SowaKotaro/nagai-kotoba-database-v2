# 共有カードの SVG を PNG に焼き、ファイルに置いて使い回すサービス。
# 焼くのは librsvg の CLI(rsvg-convert)。gem は増やさない(ReadingExtractor の MeCab と同じ方針)。
#
# 本番サーバには rsvg-convert と日本語の書体が要る(Ubuntu: librsvg2-bin / fonts-noto-cjk)。
# どちらかが無い環境(CI や導入前の本番)では available? が false になり、og:image は既定のカードのまま。
#
# セキュリティ: コマンドは配列で渡してシェルを通さない。SVG は一時ファイルで渡す。
# 置き場: tmp/cache/share_cards。本番は Capistrano の linked_dirs(tmp/cache)なのでデプロイをまたいで残る。
#   ファイル名は「名前-版.png」で、版(SVG の digest)が変われば別のファイルになる。古い版は焼いたときに消す。
#   Rails.cache(本番は :memory_store)に画像を載せると、全件出力などのキャッシュを追い出してしまうので使わない。
class ShareCardRenderer
  require "open3"

  COMMAND = [ "rsvg-convert", "--format", "png" ].freeze
  # 秒。これを超えたら打ち切って既定のカードに任せる(Puma のスレッドを握り続けない)。
  TIMEOUT = 10
  DEFAULT_DIRECTORY = Rails.root.join("tmp/cache/share_cards")
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze
  # 焼くのはプロセス内で同時に 1 本まで(Issue 89)。共有カードの URL は誰でも叩けるので、
  # 未生成の語を並べて叩かれると、Puma のスレッドの数だけ rsvg-convert が並んで CPU を握られる。
  # 先客がいれば待たずに nil を返し、呼び出し側は既定のカードに回す(クローラは後で取り直す)。
  RENDER_LOCK = Mutex.new

  # rsvg-convert が動き、日本語の書体が入っているか。プロセスごとに 1 回だけ調べる
  # (本番で導入したら Puma を再起動する)。
  def self.available?
    return @available if defined?(@available)

    @available = runnable?("rsvg-convert", "--version") && japanese_font_installed?
  end

  def self.runnable?(*command)
    system(*command, out: File::NULL, err: File::NULL) || false
  end

  # 書体が無くても rsvg-convert は豆腐(□)のまま焼いてしまうので、先に確かめる。
  def self.japanese_font_installed?
    output, status = Open3.capture2("fc-list", ":lang=ja", "family")
    status.success? && output.strip.present?
  rescue SystemCallError
    false
  end

  def initialize(directory: DEFAULT_DIRECTORY, command: COMMAND, timeout: TIMEOUT)
    @directory = Pathname(directory)
    @command = command
    @timeout = timeout
  end

  # name の版 version の PNG(バイト列)を返す。まだ焼いていなければ svg を焼いて置く。焼けなければ nil。
  def fetch(name:, version:, svg:)
    path = @directory.join("#{name}-#{version}.png")
    return unless path.exist? || render_exclusively(name, svg, path)

    path.binread
  rescue Errno::ENOENT
    nil # 読む直前に、別のリクエストが新しい版を焼いてこの版を消した
  end

  private

  def render_exclusively(name, svg, path)
    return false unless RENDER_LOCK.try_lock

    begin
      return true if path.exist? # 待っている間ではなく、直前に別のリクエストが焼き終えていた

      FileUtils.mkdir_p(@directory)
      return false unless render(svg, path)

      remove_other_versions(name, keep: path)
      true
    ensure
      RENDER_LOCK.unlock
    end
  end

  # 書き終えたファイルだけを置く(同時に取りに来たリクエストに書きかけを渡さない)。
  def render(svg, path)
    partial = "#{path}.#{SecureRandom.hex(4)}.tmp"
    Tempfile.create([ "share_card", ".svg" ], @directory) do |svg_file|
      svg_file.write(svg)
      svg_file.close
      return false unless run(svg_file.path, partial) && png?(partial)
    end
    File.rename(partial, path)
    true
  rescue SystemCallError => error
    Rails.logger.warn("[ShareCardRenderer] #{error.class}: #{error.message}")
    false
  ensure
    FileUtils.rm_f(partial) if partial
  end

  # 標準出力をそのまま PNG のファイルへ流す。TIMEOUT を過ぎたら止める。
  def run(svg_path, output_path)
    pid = Process.spawn(*@command, svg_path, out: output_path, err: File::NULL)
    waiter = Process.detach(pid)
    return waiter.value.success? if waiter.join(@timeout)

    kill(pid)
    waiter.join
    Rails.logger.warn("[ShareCardRenderer] #{@timeout} 秒で打ち切りました: #{output_path}")
    false
  end

  def kill(pid)
    Process.kill(:KILL, pid)
  rescue Errno::ESRCH
    nil # 打ち切る前に終わっていた
  end

  def png?(path)
    File.binread(path, PNG_SIGNATURE.bytesize) == PNG_SIGNATURE
  end

  def remove_other_versions(name, keep:)
    Dir.glob(@directory.join("#{name}-*.png").to_s).each do |file|
      FileUtils.rm_f(file) unless file == keep.to_s
    end
  end
end
