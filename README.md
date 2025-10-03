# CKPool Solo Mining Monitor Bot

A Telegram bot that monitors CKPool solo mining operations and provides daily reports.

## Features

- **Worker Management**: Add/remove workers with BTC addresses
- **Real-time Status**: Check current mining status instantly
- **Daily Reports**: Automated reports at user-specified times (UTC)
- **Block Discovery Alerts**: Notifications when blocks are found
- **Multi-worker Support**: Monitor multiple workers per user

## Setup

### 1. Get Telegram Bot Token

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Use `/newbot` command to create a bot
3. Set bot name and username
4. Copy the provided token

### 2. Environment Configuration

Create a `.env` file:

```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
```

### 3. Docker Deployment

```bash
# Build and start
docker-compose up --build

# Run in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

## Commands

- `/start` - Start the bot
- `/add_worker <address.worker_name>` - Add worker (e.g., `3LKS...6ESwy.miner1`)
- `/remove_worker <worker_name>` - Remove worker
- `/list_workers` - List all workers
- `/check` or `/now` - Check current mining status
- `/set_time_now` - Set daily report time to current UTC time
- `/status` - View current settings
- `/stop` - Stop notifications
- `/help` - Show available commands

## Requirements

- Docker and Docker Compose
- Valid Telegram Bot Token
- Internet connection for CKPool API access

## Tech Stack

- Ruby 3.2
- SQLite database
- Docker containerization
- CKPool API integration