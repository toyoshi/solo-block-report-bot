# Telegram Echo Bot

シンプルな鸚鵡返し（エコー）Telegram botのRuby実装です。Docker内で動作します。

## 機能

ユーザーが送信したメッセージをそのまま返信するシンプルなボットです。

## セットアップ

### 1. Telegram Bot Tokenの取得

1. Telegramで[@BotFather](https://t.me/botfather)を検索
2. `/newbot`コマンドでボットを作成
3. ボット名とユーザー名を設定
4. 発行されたトークンをコピー

### 2. 環境設定

`.env`ファイルのトークンを更新：

```bash
TELEGRAM_BOT_TOKEN=あなたのボットトークン
```

### 3. Dockerでの起動

```bash
# イメージのビルド
docker-compose build

# ボットの起動
docker-compose up

# バックグラウンドで起動する場合
docker-compose up -d

# ログの確認
docker-compose logs -f

# 停止
docker-compose down
```

## 開発

ローカルでの実行（Dockerを使わない場合）：

```bash
# 依存関係のインストール
bundle install

# ボットの起動
ruby bot.rb
```

## ファイル構成

- `bot.rb` - メインのボットアプリケーション
- `Gemfile` - Ruby依存関係
- `Dockerfile` - Dockerコンテナ設定
- `docker-compose.yml` - Docker Compose設定
- `.env` - 環境変数（Gitで管理されません）
- `.gitignore` - Git除外ファイル

## 使い方

1. ボットを起動
2. Telegramでボットを検索（@あなたのボット名）
3. メッセージを送信
4. ボットが同じメッセージを返信

## 注意事項

- `.env`ファイルは絶対にGitにコミットしないでください
- トークンは安全に管理してください