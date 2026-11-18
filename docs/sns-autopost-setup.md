# SNS の自動投稿の準備（アカウントと API）

収録語を SNS に 1 時間に 1 回、自動で投稿するための、**オーナーが行う準備**（アカウントの作成から、API の鍵を揃えるまで）の手順書。
アプリ側の実装（投稿する語の選び方・送信・トークンの自動更新・死活監視）はこの文書の外で、Issue で扱う。

- 調べた日: 2026-11-18。各 SNS の画面の名前と手順は変わりやすいので、作業する日に画面で確かめる。
- **不明** と書いた所は、調べても確かめられなかった所。作業しながら分かったら、この文書を直す。
- 方針と実装の進み具合の正は [`issues.md`](issues.md) の Issue 113（Issue 47 は統合した）。
- **鍵・パスワード・トークンは、この文書にも、チャットにも、リポジトリにも書かない。** 置き場所は実装のときに決める（本番サーバの上）。

## 0. 前提（2026-11-17〜18 にオーナーと決めたこと）

- 投稿先は **X・Threads・Bluesky** の 3 つ。Mastodon は後回し（未収載ではフォロワー 0 から見つからない。個人サーバも連合に届かない）。
  mixi2 はやらない（2026-11-18 決定。招待制で、つながりの密な場に bot は釣り合わない）。
- 1 時間に 1 回、深夜も。本文はテキストだけで、3 つとも同じ時刻に同じ語・同じ形。語はシャッフルした順に出し、一巡するまで重ねない。
- 本文は**表層形と読み（読みの文字数つき）だけ**（2026-11-18 決定）。意味は返信のリンク先で読ませる。
  ```
  寿限無寿限無五劫の擦り切れ
  ジュゲムジュゲムゴコウノスリキレ（16文字）
  ```
- サイトへの導線はプロフィールのリンクと、投稿への返信（ツリー）。**X だけは返信に URL を付けない**（URL を含む投稿は 1 件 0.20 ドル。
  毎時だと月 144 ドル）。代わりに URL つきの投稿を 1 本だけ手で出して固定する。
- 費用は X の API だけ（URL を含まない投稿 1 件 0.015 ドル × 月 720 件 ≒ 10.8 ドル。料金は Issue 113 に 2026-11-13 に確かめた記録）。
- **アカウントは、名義の変更（Issue 111）で新しい Gmail を取った後に作る。**

## 1. 共通の準備

1. 新しい Gmail を作る（Issue 111）。2 段階認証を有効にし、復旧の手段（予備のコードなど）を控える。
2. パスワードマネージャを用意する（SNS 3 つ＋開発者サイト 2 つ＋各種の鍵を持つことになる。Threads は Instagram も）。
3. 先に決めておくこと:
   - **ハンドル（@名前）**: 揃えない（2026-11-18 決定。Bluesky は `_` が使えず、X は 15 字までで、揃えようがない）。
     X は `nagaikotoba_bot`、Bluesky は `nagai-kotoba-bot.bsky.social`（作成済み）。Threads は Instagram のアカウント名になる。
   - プロフィール（2026-11-18 決定。3 つの SNS で同じ）:
     - 表示名: `長い言葉bot`
     - 説明: 「読みが10文字以上の単語を1時間に1回投稿します。」「詳細は「長い言葉のデータベース」で。」の 2 行
     - リンク: `https://nagai-kotoba-database.jp`（説明とは別の欄に置く）
     - 代名詞: 空けておく
     - アイコン: 白地に黒（`#000`）の「長」を、円より大きく 10 度傾けて置き、縁で切ったもの（1000×1000）
     - 背景（横長）: 「長い言葉の壁」（3000×1000。共有カードの背景と同じ語と色。`config/share_card_wall.json`）。
       プロフィールでは上下が切られて 1:3.5 ほどで見えるので、字は共有カードより小さくして行を増やした
     - 画像はリポジトリに入れていない（作った PNG はオーナーの手元にある）

### Google でログインできるか

オーナーの希望は「認証は基本的に Google で通す」。調べた範囲では、Google のボタンで登録できると言えるのは X だけで、
ほかは **Gmail のアドレスをメールとして使って登録する**形になる見込み。

| SNS | Google で登録 | 登録に使うもの |
|---|---|---|
| X | できる | Google アカウント |
| Threads | 無い見込み（**不明**） | Instagram のアカウント（§3） |
| Bluesky | 無い見込み（**不明**。調べた手順はどれもメールとパスワード） | メール・パスワード・生年月日 |

## 2. X

### アカウント
1. x.com で Google を使って登録する。
2. プロフィール（表示名・文面・アイコン・サイトの URL）を整え、2 段階認証を有効にする。
3. 「自動化されたアカウント」のラベルを付ける（X の作法）。設定のアカウント情報の中に「自動化」があり、管理するアカウントを指定する。
   - 管理するアカウントには人の X アカウントが要り、プロフィールに表示される。2026-11-18 に付けた。

### API（2026-11-18 にこの手順で通った）
4. サイトのアカウントで開発者コンソール（<https://console.x.com>）に入り、開発者契約に同意して、用途を書く。
   - **用途は 100 字以上が要る**。日本語の次の文（208 字）で、審査待ちにならずにすぐダッシュボードが出た。
     > 自分が運営する辞書サイト「長い言葉のデータベース」（https://nagai-kotoba-database.jp）に収録している、読みが10文字以上の日本語の単語を、このアカウントから1時間に1回、テキストだけで自動投稿します。APIは投稿の作成にだけ使います。ほかのアカウントの投稿やユーザー情報の取得・分析、いいね・返信・フォロー・DMの自動化は行いません。取得したデータを第三者に提供することもありません。
5. 支払い方法を登録する（Billing information。カードを保存するだけなら課金されない）。**JCB で払えた**。
   - 無料クレジット: 最初に保存したカードでクレジットを初めて買うと 20 ドル、初めての自動チャージに最大 50 ドルが付く（2026-10 からの告知。
     3 か月で失効。プリペイドカードは対象外）。25 ドルを買って 20 ドルが付き、45 ドルになった。
   - **自動チャージは切っておく**。残高が 0 になると API が 402 を返して投稿が止まるだけなので、使いすぎは起きない（止まったことは死活監視で知る）。
6. クレジットを買う（目安は月 11 ドル）。
7. アプリの「ユーザー認証の設定（User authentication settings）」で、権限を **読み取りと書き込み（Read and write）**、種類を Web App, Automated App or Bot にする。
   コールバック URL とサイトの URL は、どちらもサイトの URL（使わないが必須）。プライバシーポリシーは `/privacy`。
8. 「Keys & Tokens」のタブで、**OAuth 1.0 キー**の 2 段だけを発行して控える（どれも 1 度しか表示されない）。
   - コンシューマーキー（「再生成」）: **API Key・API Key Secret**。作り直すと、それより前のアクセストークンは使えなくなるので、先に作る。
   - アクセストークン（「生成する」）: **Access Token・Access Token Secret**。欄に「@<ハンドル>用 読み取りと書き込み」と出ていれば権限は正しい。
   - アプリ専用認証（ベアラートークン）と OAuth 2.0 キーは使わない。
   - この方式（OAuth 1.0a）の鍵には期限が無い。パスワードを変えたり、連携を外したりすると無効になる。
9. URL つきの投稿を 1 本、アプリから手で出してプロフィールに固定する（手で出す投稿は無料）。

### 不明な点
- 本文にドメイン名（`nagai-kotoba-database.jp`）を書くと、URL を含む投稿（0.20 ドル）として数えられるか（いまの本文には入れていない）。

## 3. Threads

### アカウント
1. Instagram のアカウントを Gmail で作る（サイトの名義で。Threads は従来、Instagram のアカウントから作る）。
   - 対応する地域では Instagram を使わず、メールか Facebook で Threads を作れる選択肢がある、という情報もある。**日本で出るかは不明**。
2. Threads のアプリで、その Instagram のアカウントからプロフィールを作る。2 段階認証を有効にする。

### API
3. Meta for Developers（<https://developers.facebook.com>）に開発者として登録する。
   - **Facebook のアカウントが要るかは不明**（従来は要った）。要る場合、Facebook の個人アカウントは本名が原則なので、
     **オーナー個人の Facebook アカウントで開発者登録し、サイトの Threads アカウントは「テスター」として足す**形になる見込み。
     開発者のアカウントは外には出ない。
4. アプリを作り、ユースケースに「Threads API へのアクセス」を選ぶ。権限に `threads_basic` と `threads_content_publish` を足す。
5. アプリの役割で、サイトの Threads アカウントを **Threads テスター**に足す。続けて Threads 側で、設定 → アカウント → ウェブサイトのアクセス許可を開き、
   届いた招待を承認する（承認を忘れると、トークンを作るときに「テスターではない」の類のエラーになる）。
6. ユースケースの設定にある User Token Generator で、テスターのアカウントのトークンを作る。
   - **作られるトークンの期限は不明**（1 時間で切れる短期のトークンだという情報と、テスターには 60 日の長期のトークンが出るという情報がある）。
     短期なら、すぐに長期のトークン（60 日）に交換する。交換はアプリの実装か、手順を渡して行う。
7. 控えるもの: **App ID・App Secret・長期のトークン**。
   - 長期のトークンは、発行から 24 時間たてば更新でき、更新するとまた 60 日になる。60 日のあいだ更新しないと失効して、更新もできなくなる。
     **更新はアプリが自動で行う**（実装の範囲）。失効したら 5〜6 をやり直す。
   - 自分のアカウントにだけ投稿するので、アプリは開発モードのままでよく、Meta の審査（App Review）は要らない。

### 投稿の上限
- 24 時間で 250 件（返信は別に 1,000 件）。毎時の投稿＋返信なら余裕がある。

### 不明な点
- 日本で Instagram 無しに作れるか。開発者登録に Facebook が要るか。User Token Generator が出すトークンの期限。
- 返信に URL を書いたときに、リンクのカードが出るか。

## 4. Bluesky

### アカウント
1. <https://bsky.app> で、Gmail のアドレス・パスワード・生年月日を入れて登録する（招待コードは要らない）。
2. ハンドルを決める。既定は `<名前>.bsky.social`。
   - サイトのドメイン（例 `nagai-kotoba-database.jp`）をハンドルにもできる。DNS に TXT レコード（`_atproto`）を足す作業が要り、
     Cloudflare の DNS を触るのはオーナー。サイトの公式アカウントだと一目で分かる。
3. プロフィールに、自動投稿の bot であることを書く（Bluesky は bot の明示を勧めている）。
   bot であることを示す専用の設定があるかは **不明**。
4. 2 段階認証（ログインのときにメールのコードを求める設定）を有効にする。

### API
5. 設定 → プライバシーとセキュリティ → アプリパスワード で、名前（例「自動投稿」）を付けて発行する。
   **発行した文字列は 1 度しか表示されない**ので、その場でパスワードマネージャに控える。
6. 控えるもの: **ハンドル・アプリパスワード**。アプリパスワードに期限は無く、消せばその場で無効になる。
   アプリは投稿のたびに、これでログインし直す。

### 不明な点
- Google で登録できるか（調べた範囲では見当たらない）。bot の専用の表示があるか。メニューの名前（「詳細設定」の下にあるという情報もある）。

## 5. 鍵が揃ったら（本番で動かす）

鍵は、手元でも本番でも `~/.config/nagai-kotoba/sns.env`（リポジトリの外。権限 600）に `export 名前=値` の行で置く。
変数の名前は [`overview.md`](overview.md) §8 の `SNS_*`。本番では Puma ではなく cron が読むので、Puma の override.conf には書かない。
入口は `bin/sns-post`（この鍵のファイルを読み、rbenv の PATH を通して `bin/rails sns:post` を動かす。引数はそのまま渡る）。

以下、`SSH` は `ssh -i ~/.ssh/nagai_kotoba_database_deploy deploy@133.167.71.10` の略。

1. 鍵のファイルを本番に置く（手元で作って確かめたものを写す）。
   ```
   SSH mkdir -p -m 700 .config/nagai-kotoba
   scp -i ~/.ssh/nagai_kotoba_database_deploy ~/.config/nagai-kotoba/sns.env deploy@133.167.71.10:.config/nagai-kotoba/sns.env
   SSH chmod 600 .config/nagai-kotoba/sns.env
   ```
2. 送らずに文面と送り先を確かめる: `SSH /var/www/nagai-kotoba-database/current/bin/sns-post DRY_RUN=1`
3. 手で 1 回送る: `SSH /var/www/nagai-kotoba-database/current/bin/sns-post`。語を決めて出すときは `WORD_ID=<語の id>` を付ける
   （いまの時刻の枠がまだ無いときだけ効く。最初の投稿は「天上天下唯我独尊」（id 1）にした）。
4. 毎時の crontab を登録する（`SSH` で入って `crontab -e`）。正時に動かし、ログは shared の log に残す。
   ```
   0 * * * * /var/www/nagai-kotoba-database/current/bin/sns-post >> /var/www/nagai-kotoba-database/shared/log/sns.log 2>&1
   ```
5. SNS を足すときは、鍵のファイルに行を足すだけでよい（cron はそのまま）。最初はその SNS だけ手で確かめる。
6. 死活監視（healthchecks.io の型。投稿が成功するたびに決まった URL を叩き、途絶えたらメールで知らせる）は、まだ入れていない（Issue 113）。
   それまでは、ときどき `sns.log` と SNS のアカウントを見る。

## 出典（2026-11-18 に確認）

- X: [Getting access（docs.x.com）](https://docs.x.com/x-api/getting-started/getting-access)・[Developer apps](https://docs.x.com/fundamentals/developer-apps.md)・
  [Free credit incentives](https://docs.x.com/x-api/getting-started/free-credits)・[料金](https://docs.x.com/ja/x-api/getting-started/pricing)・
  [X 広告の請求の基本（JCB の記載は広告の話）](https://help.x.com/ja/business-and-advertising/billing-basics)
- Threads: [Long-Lived Access Tokens（Meta）](https://developers.facebook.com/docs/threads/get-started/long-lived-tokens/)・
  [Threads API Overview](https://developers.facebook.com/docs/threads/overview)・
  [The 7 errors everyone hits setting up the Threads API（DEV）](https://dev.to/hyojunlim/the-7-errors-everyone-hits-setting-up-the-threads-api-and-the-exact-fixes-2bl1)・
  [How to Create a Threads Account (With or Without Instagram) in 2026](https://www.juicer.io/blog/instagram-threads-guide)
- Bluesky: [Bluesky User FAQ](https://bsky.social/about/blog/5-19-2023-user-faq)・[Bluesky Account Setup Visual Guide](https://fedica.com/blog/bluesky-account-setup-visual-guide/)
