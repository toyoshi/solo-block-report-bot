#!/usr/bin/env ruby

require 'telegram/bot'
require 'dotenv/load'
require 'httparty'
require 'json'
require 'time'
require 'rufus-scheduler'

# Load database after basic requires
require_relative 'db'

TOKEN = ENV['TELEGRAM_BOT_TOKEN']
TZ = 'Asia/Tokyo'

if TOKEN.nil? || TOKEN.empty? || TOKEN == 'YOUR_BOT_TOKEN_HERE'
  puts 'Error: Please set TELEGRAM_BOT_TOKEN in .env file'
  puts 'Get your bot token from @BotFather on Telegram'
  exit 1
end

# Database ready

# BTC address validation
def valid_btc_address?(addr)
  !!(addr =~ /^(?:[13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[02-9ac-hj-np-z]{11,71})$/)
end

# Fetch CKPool data
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

# Fetch network difficulty
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

# Format timestamp
def format_timestamp(timestamp)
  return "N/A" if timestamp.nil? || timestamp == 0
  Time.at(timestamp).getlocal("+09:00").strftime("%Y-%m-%d %H:%M:%S JST")
end

# Format numbers (K, M, G, T, P units)
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

# Generate individual worker report
def generate_worker_report(worker, data, difficulty)
  return nil if data.nil?

  bestshare = (data["bestshare"] || 0).to_f
  hit_status = if difficulty && bestshare >= difficulty
    "🎉 BLOCK FOUND! 🎉"
  elsif difficulty && bestshare > 0
    progress = (bestshare / difficulty * 100).round(4)
    "📊 Progress: #{progress}%"
  else
    "📊 Progress: 0%"
  end

  lines = []
  lines << "📍 #{worker.label}"
  lines << "Address: #{worker.btc_address}"
  lines << ""
  lines << "⚡ Hashrate:"
  lines << "• 1m: #{format_number(data["hashrate1m"])}H/s"
  lines << "• 5m: #{format_number(data["hashrate5m"])}H/s"
  lines << "• 1h: #{format_number(data["hashrate1hr"])}H/s"
  lines << "• 1d: #{format_number(data["hashrate1d"])}H/s"
  lines << ""
  lines << "📊 Shares: #{data["shares"] || 0}"
  lines << "📊 Best Share: #{format_number(bestshare)}"
  lines << hit_status
  lines << ""
  lines << "🕐 Last Share: #{format_timestamp(data["lastshare"])}"

  lines.join("\n")
end

# Block discovery check
def check_block_hits(bot)
  difficulty = fetch_network_difficulty
  return if difficulty.nil?

  Worker.all.each do |worker|
    begin
      data = fetch_ckpool_data(worker.btc_address)
      next if data.nil?

      bestshare = (data["bestshare"] || 0).to_f
      next unless bestshare >= difficulty

      # Prevent duplicate notifications
      if worker.should_notify_hit?(bestshare)
        user = worker.user
        msg = "🎉🎉🎉 BLOCK FOUND! 🎉🎉🎉\n\n"
        msg += "Worker: #{worker.label}\n"
        msg += "Address: #{worker.btc_address}\n"
        msg += "Best Share: #{format_number(bestshare)}\n"
        msg += "Network Difficulty: #{format_number(difficulty)}\n"
        msg += "\n🔗 https://solo.ckpool.org/users/#{worker.btc_address}"

        send_message(bot, user.chat_id, msg)
      end
    rescue => e
      puts "Error checking worker #{worker.id}: #{e.message}"
    end
  end
end

# Send daily report
def send_daily_report(bot, user)
  workers = user.active_workers
  return if workers.empty?

  difficulty = fetch_network_difficulty

  lines = ["📝 日次レポート (#{Time.now.getlocal("+09:00").strftime("%Y-%m-%d")})"]
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

  send_message(bot, user.chat_id, lines.join("\n"))
rescue => e
  puts "Error sending daily report to #{user.chat_id}: #{e.message}"
end

# Start scheduler
def start_scheduler(bot)
  scheduler = Rufus::Scheduler.new

  # Every 5 minutes: Check for block discoveries
  scheduler.every '5m' do
    puts "[#{Time.now}] Checking for block hits..."
    check_block_hits(bot)
  end

  # Every minute: Check for daily report delivery
  scheduler.every '1m' do
    now = Time.now.getlocal("+09:00")
    User.where(active: true, hour: now.hour, minute: now.min).each do |user|
      puts "[#{Time.now}] Sending daily report to #{user.chat_id}"
      send_daily_report(bot, user)
    end
  end

  scheduler
end

# Message sending helper (for consistency)
def send_message(bot, chat_id, text)
  bot.api.send_message(chat_id: chat_id, text: text)
end

# Main bot processing
puts "Starting CKPool Monitor Bot..."
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

    # Get or create user
    user = User.find_or_create(chat_id, username: username, first_name: first_name)

    case text
    when '/start'
      user.update(active: true)
      user.log_command('start')

      welcome_msg = "👋 Welcome to CKPool Solo Mining Monitor Bot!\n\nAvailable commands:\n• /add_worker - Add worker\n• /help - Show help\n• /status - Check settings"

      send_message(bot, chat_id, welcome_msg)

    when '/add_worker'
      user.log_command('add_worker', 'help_requested')
      help_msg = "📋 How to use /add_worker:\n\n/add_worker <label> <BTC_address>\n\nExample: /add_worker miner1 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy"
      send_message(bot, chat_id, help_msg)

    when /^\/add_worker\s+(\S+)\s+(\S+)$/
      label, btc_address = $1, $2
      user.log_command('add_worker', "#{label} #{btc_address}")

      unless valid_btc_address?(btc_address)
        send_message(bot, chat_id, "❌ Invalid BTC address.")
        next
      end

      existing = Worker.find_by_label(chat_id, label)
      if existing
        existing.update(btc_address: btc_address, updated_at: Time.now)
        msg = "✅ Worker '#{label}' updated.\nAddress: #{btc_address}"
      else
        Worker.create(chat_id: chat_id, label: label, btc_address: btc_address)
        msg = "✅ Worker '#{label}' added.\nAddress: #{btc_address}"
      end

      send_message(bot, chat_id, msg)

    when /^\/remove_worker\s+(\S+)$/
      label = $1
      user.log_command('remove_worker', label)

      worker = Worker.find_by_label(chat_id, label)
      if worker
        worker.destroy
        msg = "✅ Worker '#{label}' removed."
      else
        msg = "❌ Worker '#{label}' not found."
      end

      bot.api.send_message(chat_id: chat_id, text: msg)

    when '/list_workers'
      user.log_command('list_workers')

      workers = user.active_workers
      if workers.empty?
        msg = "📋 No workers registered."
      else
        lines = ["📋 Registered Workers:"]
        workers.each do |w|
          lines << "• #{w.label}: #{w.btc_address}"
        end
        msg = lines.join("\n")
      end

      send_message(bot, chat_id, msg)

    when '/check', '/now'
      user.log_command('check')

      workers = user.active_workers
      if workers.empty?
        send_message(
          bot, chat_id,
          "❌ No workers registered.\nPlease add a worker using /add_worker."
        )
        next
      end

      send_message(bot, chat_id, "📊 Fetching data... (#{workers.size} workers)")

      difficulty = fetch_network_difficulty
      lines = ["📈 Current Mining Status"]
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
        lines << "🎯 Network Difficulty: #{format_number(difficulty)}"
      end

      lines << ""
      lines << "⏰ Generated at: #{Time.now.getlocal("+09:00").strftime("%Y-%m-%d %H:%M:%S JST")}"

      send_message(bot, chat_id, lines.join("\n"))

    when /^\/time\s+(\d{1,2}):(\d{2})$/
      hour, minute = $1.to_i, $2.to_i
      user.log_command('time', "#{hour}:#{minute}")

      if (0..23).include?(hour) && (0..59).include?(minute)
        user.update(hour: hour, minute: minute, active: true)
        msg = "✅ Daily report time set to #{"%02d:%02d" % [hour, minute]} JST."
      else
        msg = "❌ Invalid time format. Please use HH:MM format (example: 09:00)"
      end

      send_message(bot, chat_id, msg)

    when '/status'
      user.log_command('status')

      workers = user.active_workers
      lines = ["📊 Current Settings:"]
      lines << ""
      lines << "• Daily Report: #{"%02d:%02d" % [user.hour, user.minute]} JST"
      lines << "• Status: #{user.active ? "Active ✅" : "Inactive ❌"}"
      lines << "• Registered Workers: #{workers.size}"

      if workers.any?
        lines << ""
        lines << "Workers:"
        workers.each do |w|
          lines << "• #{w.label}: #{w.btc_address[0..20]}..."
        end
      end

      send_message(bot, chat_id, lines.join("\n"))

    when '/stop'
      user.log_command('stop')
      user.update(active: false)

      send_message(bot, chat_id, "🔕 Notifications stopped.\nSend /start to resume.")

    when '/help'
      # Simplified help - no markdown to avoid parsing errors
      help_msg = "📋 Available Commands:\n\n• /start - Start bot\n• /help - Show help\n• /add_worker <label> <BTC_address> - Add worker\n• /remove_worker <label> - Remove worker\n• /list_workers - List workers\n• /check, /now - Check current status\n• /time <HH:MM> - Set daily report time\n• /status - Check settings\n• /stop - Stop notifications"

      send_message(bot, chat_id, help_msg)

    else
      send_message(bot, chat_id, "❓ Unknown command.\nUse /help to see available commands.")
    end

  rescue => e
    error_message = "Error handling message from #{chat_id}: #{e.message}"
    puts error_message
    puts "Backtrace:"
    puts e.backtrace.first(10).join("\n")

    begin
      detailed_error = "⚠️ An error occurred\nDetails: #{e.class.name}\nPlease try again later."
      send_message(bot, chat_id, detailed_error)
    rescue => send_error
      puts "Failed to send error message: #{send_error.message}"
    end
  end

  scheduler.shutdown(:wait) if scheduler
end