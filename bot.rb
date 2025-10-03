#!/usr/bin/env ruby

require 'telegram/bot'
require 'dotenv/load'
require 'httparty'
require 'json'
require 'time'

token = ENV['TELEGRAM_BOT_TOKEN']

if token.nil? || token.empty? || token == 'YOUR_BOT_TOKEN_HERE'
  puts 'Error: Please set TELEGRAM_BOT_TOKEN in .env file'
  puts 'Get your bot token from @BotFather on Telegram'
  exit 1
end

# ハードコードされたBTCアドレス（あなた専用）
BTC_ADDRESS = '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy'

def fetch_ckpool_data
  url = "https://solo.ckpool.org/users/#{BTC_ADDRESS}"
  puts "Fetching CKPool data from: #{url}"
  response = HTTParty.get(url, timeout: 20)

  if response.code == 200
    data = JSON.parse(response.body)
    puts "CKPool data fetched successfully: #{data.keys.join(', ')}"
    data
  else
    raise "CKPool API error: #{response.code}"
  end
rescue => e
  puts "Error fetching CKPool data: #{e.message}"
  puts e.backtrace.first(3).join("\n")
  nil
end

def fetch_network_difficulty
  url = "https://blockchain.info/q/getdifficulty"
  puts "Fetching network difficulty from: #{url}"
  response = HTTParty.get(url, timeout: 10)

  if response.code == 200
    difficulty = response.body.strip.to_f
    puts "Network difficulty fetched: #{difficulty}"
    difficulty
  else
    raise "Blockchain.info API error: #{response.code}"
  end
rescue => e
  puts "Error fetching difficulty: #{e.message}"
  puts e.backtrace.first(3).join("\n")
  nil
end

def format_timestamp(timestamp)
  return "N/A" if timestamp.nil? || timestamp == 0
  Time.at(timestamp).getlocal("+09:00").strftime("%Y-%m-%d %H:%M:%S JST")
end

def format_number(num)
  return "0" if num.nil? || num == 0

  # 文字列の場合は数値に変換
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

def generate_report
  data = fetch_ckpool_data
  difficulty = fetch_network_difficulty

  if data.nil?
    return "⚠️ CKPool APIからデータを取得できませんでした。"
  end

  # ブロック発見判定
  bestshare = (data["bestshare"] || 0).to_f
  hit_status = if difficulty && bestshare >= difficulty
    "🎉 **ブロック発見！** 🎉"
  elsif difficulty && bestshare > 0
    progress = (bestshare / difficulty * 100).round(2)
    "📊 進捗: #{progress}%"
  else
    "📊 進捗: 0%"
  end

  report = []
  report << "📈 **マイニングステータスレポート**"
  report << "━━━━━━━━━━━━━━━━━━━━"
  report << ""
  report << "📍 **アドレス:**"
  report << "`#{BTC_ADDRESS}`"
  report << "🔗 [CKPoolで詳細を見る](https://solo.ckpool.org/users/#{BTC_ADDRESS})"
  report << ""

  report << "⚡ **ハッシュレート:**"
  report << "• 1分: #{format_number(data["hashrate1m"])}H/s"
  report << "• 5分: #{format_number(data["hashrate5m"])}H/s"
  report << "• 1時間: #{format_number(data["hashrate1hr"])}H/s"
  report << "• 1日: #{format_number(data["hashrate1d"])}H/s"
  report << "• 7日: #{format_number(data["hashrate7d"])}H/s"
  report << ""

  report << "📊 **シェア情報:**"
  report << "• 累計シェア: #{data["shares"] || 0}"
  report << "• ベストシェア: #{format_number(bestshare)}"
  report << "• 過去最高: #{format_number(data["bestever"] || 0)}"
  report << ""

  if difficulty
    report << "🎯 **ネットワーク難易度:**"
    report << "• #{format_number(difficulty)}"
    report << ""
    report << "📍 **ブロック発見状況:**"
    report << "• #{hit_status}"
    report << ""
  end

  report << "🕐 **最終アクティビティ:**"
  report << "• 最終シェア: #{format_timestamp(data["lastshare"])}"
  report << "• 承認日時: #{format_timestamp(data["authorised"])}"
  report << ""

  report << "⏰ レポート生成: #{Time.now.getlocal("+09:00").strftime("%Y-%m-%d %H:%M:%S JST")}"

  report.join("\n")
end

puts 'Starting CKPool Monitor Bot...'
puts 'Bot is running. Press Ctrl+C to stop.'

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      if message.text
        puts "[#{Time.now}] #{message.from.first_name}: #{message.text}"

        case message.text
        when '/start'
          welcome_message = <<~MSG
            👋 CKPool Solo Mining Monitor Botへようこそ！

            このボットは以下のアドレスのマイニング状況を監視します：
            `#{BTC_ADDRESS}`

            📋 **使用可能なコマンド:**
            /status または /report - マイニング状況レポートを取得
            /help - このヘルプメッセージを表示

            レポートを取得するには /status または /report を送信してください。
          MSG

          bot.api.send_message(
            chat_id: message.chat.id,
            text: welcome_message,
            parse_mode: 'Markdown'
          )

        when '/status', '/report'
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "📊 レポートを生成中..."
          )

          begin
            report = generate_report

            bot.api.send_message(
              chat_id: message.chat.id,
              text: report,
              parse_mode: 'Markdown',
              disable_web_page_preview: true
            )
          rescue => e
            error_message = "⚠️ エラーが発生しました:\n#{e.message}\n\nスタックトレース:\n#{e.backtrace.first(5).join("\n")}"
            puts error_message

            bot.api.send_message(
              chat_id: message.chat.id,
              text: "⚠️ レポート生成中にエラーが発生しました。\n詳細: #{e.message}"
            )
          end

        when '/help'
          help_message = <<~MSG
            📋 **使用可能なコマンド:**

            /status または /report - マイニング状況レポートを取得
            /help - このヘルプメッセージを表示
            /start - ウェルカムメッセージを表示

            監視対象アドレス:
            `#{BTC_ADDRESS}`
          MSG

          bot.api.send_message(
            chat_id: message.chat.id,
            text: help_message,
            parse_mode: 'Markdown'
          )

        else
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "❓ 不明なコマンドです。/help でコマンド一覧を確認してください。"
          )
        end
      end
    end
  rescue StandardError => e
    puts "Error handling message: #{e.message}"
  end
end