# Aki v0.1

候補日への○×ではなく、空いている日にだけ予定を置く日程調整ツール。

## 構成

- GitHub Pages: `index.html`, `config.js`
- Supabase: `supabase.sql`
- ログインなし
- イベントごとに `?e=<UUID>` の共有URL
- 終日がデフォルト。必要なときだけ時間指定
- 複数日をまとめて入力
- 15秒ごと＋タブ復帰時に自動同期
- 自分のブラウザから追加した予定だけ削除可能

## セットアップ

1. SupabaseでFreeプロジェクトを作る。
2. SQL Editorで `supabase.sql` を実行する。
3. SupabaseのProject URLとPublishable keyを `config.js` に入れる。
4. このフォルダをGitHubリポジトリのルートに置く。
5. GitHubの Settings → Pages で `main` / root を公開する。

`config.js` のPublishable keyはブラウザに置く前提のキー。Secret keyは絶対に置かない。

## URL

トップページからイベントを作ると、以下のようなURLになる。

`https://<user>.github.io/<repo>/?e=<uuid>`

そのURLを共有すれば、全員が同じ予定を読み書きできる。

## 自動keepalive

`.github/workflows/keepalive.yml` がSupabaseの停止対策を行う。

- 1日3回、読み取りRPCに軽いリクエストを送る（データは増えない）。
- 毎月1日に `.keepalive` を更新してコミットし、公開リポジトリが60日無活動でscheduled workflowを自動停止するのを避ける。
- GitHub Actionsの手動実行（workflow_dispatch）にも対応。

