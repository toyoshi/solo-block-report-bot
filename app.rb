#!/usr/bin/env ruby

require 'telegram/bot'
require 'dotenv/load'
require 'httparty'
require 'json'
require 'time'
require 'rufus-scheduler'
require_relative 'db'

TOKEN = ENV['TELEGRAM_BOT_TOKEN']
TZ = 'Asia/Tokyo'

if TOKEN.nil? || TOKEN.empty? || TOKEN == 'YOUR_BOT_TOKEN_HERE'
  puts 'Error: Please set TELEGRAM_BOT_TOKEN in .env file'
  exit 1
end

# BTCアドレスのバリデーション
def valid_btc_address?(addr)
  !!(addr =~ /^(?:[13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[02-9ac-hj-np-z]{11,71})$/)
end

# CKPoolデータ取得
def fetch_ckpool_data(address)
  url = "https://solo.ckpool.org/users/#{address}"
  response = HTTParty.get(url, timeout: 20)

  if response.code == 200
    JSON.parse(response.body)
  else
    raise "CKPool API error: #{response.code}"
  end
rescue => e
  puts "Error fetching CKPool data: #{e.message}"
  nil
end

# ネットワーク難易度取得
def fetch_network_difficulty
  url = "https://blockchain.info/q/getdifficulty"
  response = HTTParty.get(url, timeout: 10)

  if response.code == 200
    response.body.strip.to_f
  else
    raise "Blockchain.info API error: #{response.code}"
  end
rescue => e
  puts "Error fetching difficulty: #{e.message}"
  nil
end

# タイムスタンプフォーマット
def format_timestamp(timestamp)
  return "N/A" if timestamp.nil? || timestamp == 0
  Time.at(timestamp).getlocal("+09:00").strftime("%Y-%m-%d %H:%M:%S JST")
end

# 数値フォーマット（K, M, G, T, P単位）
def format_number(num)
  return "0" if num.nil? || num == 0

  num = num.to_f if num.is_a?(String)

  if num >= 1_000_000_000_000_000
    "%.2f P" % (num / 1_000_000_000_000_000.0)
  elsif num >= 1_000_000_000_000
    "%.2f T" % (num / 1_000_000_000_000.0)
  elsif num >= 1_000_000_000
    "%.2f G" % (num / 1_000_000_000.0)
  elsif num >= 1_000_000
    "%.2f M" % (num / 1_000_000.0)
  elsif num >= 1_000
    "%.2f K" % (num / 1_000.0)
  else
    num.to_s
  end
end

# 単一ワーカーのレポート生成
def generate_worker_report(worker, data, difficulty)
  return nil if data.nil?

  bestshare = (data["bestshare"] || 0).to_f
  hit_status = if difficulty && bestshare >= difficulty
    "🎉 **ブロック発見！** 🎉"
  elsif difficulty && bestshare > 0
    progress = (bestshare / difficulty * 100).round(4)
    "📊 進捗: #{progress}%"
  else
    "📊 進捗: 0%"
  end

  lines = []
  lines << "📍 **#{worker.label}**"
  lines << "アドレス: `#{worker.btc_address}`"
  lines << ""
  lines << "⚡ ハッシュレート:"
  lines << "• 1m: #{format_number(data["hashrate1m"])}H/s | 5m: #{format_number(data["hashrate5m"])}H/s"
  lines << "• 1h: #{format_number(data["hashrate1hr"])}H/s | 1d: #{format_number(data["hashrate1d"])}H/s"
  lines << ""
  lines << "📊 シェア: #{data["shares"] || 0} | ベスト: #{format_number(bestshare)}"
  lines << hit_status
  lines << ""
  lines << "🕐 最終シェア: #{format_timestamp(data["lastshare"])}"

  lines.join("\n")
end

# ブロック発見チェック
def check_block_hits(bot)
  difficulty = fetch_network_difficulty
  return if difficulty.nil?

  Worker.all.each do |worker|
    begin
      data = fetch_ckpool_data(worker.btc_address)
      next if data.nil?

      bestshare = (data["bestshare"] || 0).to_f
      next unless bestshare >= difficulty

      # 重複通知防止
      if worker.should_notify_hit?(bestshare)
        user = worker.user
        msg = "🎉🎉🎉 **ブロック発見！** 🎉🎉🎉\n\n"
        msg += "ワーカー: #{worker.label}\n"
        msg += "アドレス: `#{worker.btc_address}`\n"
        msg += "ベストシェア: #{format_number(bestshare)}\n"
        msg += "ネットワーク難易度: #{format_number(difficulty)}\n"
        msg += "\n🔗 [CKPoolで確認](https://solo.ckpool.org/users/#{worker.btc_address})"

        bot.api.send_message(
          chat_id: user.chat_id,
          text: msg,
          parse_mode: 'Markdown',
          disable_web_page_preview: true
        )
      end
    rescue => e
      puts "Error checking worker #{worker.id}: #{e.message}"
    end
  end
end

# 日次レポート送信
def send_daily_report(bot, user)
  workers = user.active_workers
  return if workers.empty?

  difficulty = fetch_network_difficulty

  lines = ["📝 **日次レポート** (#{Time.now.getlocal("+09:00").strftime("%Y-%m-%d")})"]
  lines << "━━━━━━━━━━━━━━━━━━━━"
  lines << ""

  workers.each do |worker|
    data = fetch_ckpool_data(worker.btc_address)
    report = generate_worker_report(worker, data, difficulty)
    lines << report if report
    lines << "━━━━━━━━━━━━━━━━━━━━" if worker != workers.last
  end

  if difficulty
    lines << ""
    lines << "🎯 ネットワーク難易度: #{format_number(difficulty)}"
  end

  bot.api.send_message(
    chat_id: user.chat_id,
    text: lines.join("\n"),
    parse_mode: 'Markdown',
    disable_web_page_preview: true
  )
rescue => e
  puts "Error sending daily report to #{user.chat_id}: #{e.message}"
end

# スケジューラー起動
def start_scheduler(bot)
  scheduler = Rufus::Scheduler.new

  # 5分毎: ブロック発見チェック
  scheduler.every '5m' do
    puts "[#{Time.now}] Checking for block hits..."
    check_block_hits(bot)
  end

  # 毎分: 日次レポート配信チェック
  scheduler.every '1m' do
    now = Time.now.getlocal("+09:00")
    User.where(active: true, hour: now.hour, minute: now.min).each do |user|
      puts "[#{Time.now}] Sending daily report to #{user.chat_id}"
      send_daily_report(bot, user)
    end
  end

  scheduler
end

# メインボット処理
puts "Starting CKPool Monitor Bot (Full Version)..."
puts "Bot is running. Press Ctrl+C to stop."

Telegram::Bot::Client.run(TOKEN) do |bot|
  scheduler = start_scheduler(bot)

  bot.listen do |message|
    next unless message.is_a?(Telegram::Bot::Types::Message)
    next unless message.text

    chat_id = message.chat.id
    text = message.text.strip
    username = message.from.username
    first_name = message.from.first_name

    puts "[#{Time.now}] #{first_name}: #{text}"

    # ユーザー取得または作成
    user = User.find_or_create(chat_id, username: username, first_name: first_name)

    case text
    when '/start'
      user.update(active: true)
      user.log_command('start')

      welcome_msg = <<~MSG
        👋 **CKPool Solo Mining Monitor Botへようこそ！**

        📋 **使用可能なコマンド:**
        • `/add_worker <ラベル> <BTCアドレス>` - ワーカー追加
        • `/remove_worker <ラベル>` - ワーカー削除
        • `/list_workers` - ワーカー一覧
        • `/check` または `/now` - 即座に状況確認
        • `/time HH:MM` - 日次レポート時刻設定
        • `/status` - 現在の設定確認
        • `/stop` - 通知停止
        • `/help` - ヘルプ表示

        まずはワーカーを追加してください：
        例: `/add_worker main 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy`
      MSG

      bot.api.send_message(
        chat_id: chat_id,
        text: welcome_msg,
        parse_mode: 'Markdown'
      )

    when /^\/add_worker\s+(\S+)\s+(\S+)$/
      label, btc_address = $1, $2
      user.log_command('add_worker', "#{label} #{btc_address}")

      unless valid_btc_address?(btc_address)
        bot.api.send_message(
          chat_id: chat_id,
          text: "❌ 無効なBTCアドレスです。"
        )
        next
      end

      existing = Worker.find_by_label(chat_id, label)
      if existing
        existing.update(btc_address: btc_address, updated_at: Time.now)
        msg = "✅ ワーカー「#{label}」を更新しました。"
      else
        Worker.create(chat_id: chat_id, label: label, btc_address: btc_address)
        msg = "✅ ワーカー「#{label}」を追加しました。"
      end

      bot.api.send_message(chat_id: chat_id, text: msg)

    when /^\/remove_worker\s+(\S+)$/
      label = $1
      user.log_command('remove_worker', label)

      worker = Worker.find_by_label(chat_id, label)
      if worker
        worker.destroy
        msg = "✅ ワーカー「#{label}」を削除しました。"
      else
        msg = "❌ ワーカー「#{label}」が見つかりません。"
      end

      bot.api.send_message(chat_id: chat_id, text: msg)

    when '/list_workers'
      user.log_command('list_workers')

      workers = user.active_workers
      if workers.empty?
        msg = "📋 登録されているワーカーはありません。"
      else
        lines = ["📋 **登録ワーカー一覧:**"]
        workers.each do |w|
          lines << "• #{w.label}: `#{w.btc_address}`"
        end
        msg = lines.join("\n")
      end

      bot.api.send_message(
        chat_id: chat_id,
        text: msg,
        parse_mode: 'Markdown'
      )

    when '/check', '/now'
      user.log_command('check')

      workers = user.active_workers
      if workers.empty?
        bot.api.send_message(
          chat_id: chat_id,
          text: "❌ ワーカーが登録されていません。\n`/add_worker`でワーカーを追加してください。",
          parse_mode: 'Markdown'
        )
        next
      end

      bot.api.send_message(
        chat_id: chat_id,
        text: "📊 データを取得中... (#{workers.size}ワーカー)"
      )

      difficulty = fetch_network_difficulty
      lines = ["📈 **現在のマイニング状況**"]
      lines << "━━━━━━━━━━━━━━━━━━━━"
      lines << ""

      workers.each do |worker|
        data = fetch_ckpool_data(worker.btc_address)
        report = generate_worker_report(worker, data, difficulty)
        lines << report if report
        lines << "━━━━━━━━━━━━━━━━━━━━" if worker != workers.last
      end

      if difficulty
        lines << ""
        lines << "🎯 ネットワーク難易度: #{format_number(difficulty)}"
      end

      lines << ""
      lines << "⏰ 生成時刻: #{Time.now.getlocal("+09:00").strftime("%Y-%m-%d %H:%M:%S JST")}"

      bot.api.send_message(
        chat_id: chat_id,
        text: lines.join("\n"),
        parse_mode: 'Markdown',
        disable_web_page_preview: true
      )

    when /^\/time\s+(\d{1,2}):(\d{2})$/
      hour, minute = $1.to_i, $2.to_i
      user.log_command('time', "#{hour}:#{minute}")

      if (0..23).include?(hour) && (0..59).include?(minute)
        user.update(hour: hour, minute: minute, active: true)
        msg = "✅ 日次レポート配信時刻を #{"%02d:%02d" % [hour, minute]} JST に設定しました。"
      else
        msg = "❌ 無効な時刻です。HH:MM形式で入力してください（例: 09:00）"
      end

      bot.api.send_message(chat_id: chat_id, text: msg)

    when '/status'
      user.log_command('status')

      workers = user.active_workers
      lines = ["📊 **現在の設定:**"]
      lines << ""
      lines << "• 日次レポート: #{"%02d:%02d" % [user.hour, user.minute]} JST"
      lines << "• 配信状態: #{user.active ? "有効 ✅" : "無効 ❌"}"
      lines << "• 登録ワーカー数: #{workers.size}"

      if workers.any?
        lines << ""
        lines << "**ワーカー一覧:**"
        workers.each do |w|
          lines << "• #{w.label}: `#{w.btc_address[0..20]}...`"
        end
      end

      bot.api.send_message(
        chat_id: chat_id,
        text: lines.join("\n"),
        parse_mode: 'Markdown'
      )

    when '/stop'
      user.log_command('stop')
      user.update(active: false)

      bot.api.send_message(
        chat_id: chat_id,
        text: "🔕 通知を停止しました。\n再開するには `/start` を送信してください。"
      )

    when '/help'
      user.log_command('help')

      help_msg = <<~MSG
        📋 **コマンド一覧:**

        **ワーカー管理:**
        • `/add_worker <ラベル> <BTCアドレス>` - ワーカー追加
        • `/remove_worker <ラベル>` - ワーカー削除
        • `/list_workers` - ワーカー一覧表示

        **モニタリング:**
        • `/check` または `/now` - 今すぐ状況確認
        • `/time HH:MM` - 日次レポート時刻設定（例: /time 09:00）
        • `/status` - 現在の設定確認

        **その他:**
        • `/start` - ボット開始/再開
        • `/stop` - 通知停止
        • `/help` - このヘルプ表示

        **自動通知:**
        • ブロック発見時に即座に通知
        • 設定時刻に日次レポート配信
      MSG

      bot.api.send_message(
        chat_id: chat_id,
        text: help_msg,
        parse_mode: 'Markdown'
      )

    else
      bot.api.send_message(
        chat_id: chat_id,
        text: "❓ 不明なコマンドです。\n`/help` でコマンド一覧を確認してください。",
        parse_mode: 'Markdown'
      )
    end

  rescue => e
    puts "Error handling message: #{e.message}"
    puts e.backtrace.first(5)

    begin
      bot.api.send_message(
        chat_id: chat_id,
        text: "⚠️ エラーが発生しました。しばらく待ってから再度お試しください。"
      )
    rescue
      # エラー通知も失敗した場合は無視
    end
  end

  scheduler.shutdown(:wait) if scheduler
end