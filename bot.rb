#!/usr/bin/env ruby

require 'telegram/bot'
require 'dotenv/load'

token = ENV['TELEGRAM_BOT_TOKEN']

if token.nil? || token.empty? || token == 'YOUR_BOT_TOKEN_HERE'
  puts 'Error: Please set TELEGRAM_BOT_TOKEN in .env file'
  puts 'Get your bot token from @BotFather on Telegram'
  exit 1
end

puts 'Starting Telegram Echo Bot...'
puts 'Bot is running. Press Ctrl+C to stop.'

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      if message.text
        puts "[#{Time.now}] #{message.from.first_name}: #{message.text}"

        # Echo back the message
        bot.api.send_message(
          chat_id: message.chat.id,
          text: message.text
        )
      end
    end
  rescue StandardError => e
    puts "Error handling message: #{e.message}"
  end
end