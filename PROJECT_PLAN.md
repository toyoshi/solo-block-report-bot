# CKPool Solo Mining Monitor Bot - MVP実装仕様

## 概要

CKPool Soloマイニングプールの監視を行うTelegram Botの最小実装版。
ブロック発見時の即座通知と日次レポートを提供する。

## 主要機能（MVP）

### 1. ブロック発見通知
- **即時通知**: bestshare >= network_difficulty の場合に通知
- **重複防止**: 同じbestshareでの連続通知を防止（last_notified_bestshare保持）
- **チェック間隔**: 5分毎

### 2. 日次レポート
- ユーザーごとに指定時刻（JST）に配信
- 登録された全ワーカーの状況をまとめて送信
- ハッシュレート、シェア数、最終受信時刻等を含む

### 3. ワーカー管理
- 複数ワーカーの登録・削除
- ラベル付きBTCアドレス管理
- ワーカーごとの状態追跡

## コマンド一覧

- `/start` - ボット開始・再開
- `/add_worker <label> <BTCアドレス>` - ワーカー追加
- `/remove_worker <label>` - ワーカー削除
- `/list_workers` - 登録ワーカー一覧表示
- `/time HH:MM` - 日次レポート時刻設定（JST）
- `/status` - 現在の設定確認
- `/stop` - 通知配信停止

## 技術スタック

- **言語**: Ruby 3.2.2
- **フレームワーク**:
  - telegram-bot-ruby (Telegram Bot API)
  - Sequel (ORM)
  - Rufus-scheduler (定期実行)
  - Rack (ヘルスチェック用Webサーバー)
- **データベース**: PostgreSQL
- **デプロイ**: Railway

## ファイル構成

```
solo-block-report-bot/
├── app.rb        # メインアプリケーション
├── db.rb         # データベース接続・モデル定義
├── schema.sql    # データベーススキーマ
├── Gemfile       # Ruby依存関係
├── Procfile      # Railway用プロセス定義
├── .env          # 環境変数（ローカル開発用）
└── .gitignore    # Git除外設定
```

## データベース構成

### users テーブル
- ユーザー情報と日次レポート設定を管理
- chat_id (PK), hour, minute, active, timestamps

### workers テーブル
- ワーカー（BTCアドレス）情報を管理
- id (PK), chat_id (FK), label, btc_address, timestamps
- UNIQUE制約: (chat_id, label)

### hit_states テーブル
- ブロック発見通知の重複防止用状態管理
- worker_id (PK/FK), last_notified_bestshare, last_hit_at

## 外部API

### CKPool API
- エンドポイント: `https://solo.ckpool.org/users/{btc_address}`
- 取得データ: hashrate, shares, bestshare, bestever, lastshare等

### Blockchain.info API
- エンドポイント: `https://blockchain.info/q/getdifficulty`
- 取得データ: 現在のネットワーク難易度

## デプロイ設定（Railway）

### 環境変数
- `TELEGRAM_BOT_TOKEN`: Telegramボットトークン
- `DATABASE_URL`: PostgreSQL接続URL（Railway自動設定）
- `ROLE`: プロセスタイプ（web/worker）

### Procfile
```
web: bundle exec ruby app.rb
worker: ROLE=worker bundle exec ruby app.rb
```

## 実装の特徴

### MVP範囲
- ✅ ブロック発見の即座通知
- ✅ 重複通知防止
- ✅ 日次レポート機能
- ✅ 複数ワーカー対応
- ✅ Railway対応

### 将来の拡張予定
- ⏳ 低ハッシュレート警告（しきい値判定）
- ⏳ API接続エラー時の再試行処理
- ⏳ より詳細な統計・グラフ表示
- ⏳ ワーカーグループ機能

## セキュリティ考慮事項

- Telegram Bot TokenとDatabase URLは環境変数で管理
- .envファイルはGit管理外（.gitignore）
- BTCアドレスのバリデーション実装
- ユーザーブロック時の自動配信停止

## 開発・テスト

### ローカル環境セットアップ
```bash
# 依存関係インストール
bundle install

# PostgreSQL起動（Docker使用例）
docker run -d -p 5432:5432 \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=ckpool_bot \
  postgres:15

# 環境変数設定
export DATABASE_URL="postgres://postgres:password@localhost:5432/ckpool_bot"
export TELEGRAM_BOT_TOKEN="your_bot_token"

# 起動
ruby app.rb
```

### Railway デプロイ
1. GitHubリポジトリ連携
2. PostgreSQLアドオン追加
3. 環境変数設定（TELEGRAM_BOT_TOKEN）
4. デプロイ実行

## 制約事項・注意点

- チェック間隔は5分（CKPool API負荷を考慮）
- 日次レポートは1分精度（秒単位指定不可）
- タイムゾーンはJST固定
- 初期実装では再試行処理なし（エラー時は次回実行を待つ）