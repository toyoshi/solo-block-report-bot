require_relative 'test_helper'

# Mock Telegram Bot for integration testing
class MockTelegramBot
  attr_reader :sent_messages, :api

  def initialize
    @sent_messages = []
    @api = MockTelegramAPI.new(@sent_messages)
  end

  def clear_messages
    @sent_messages.clear
  end
end

class MockTelegramAPI
  def initialize(sent_messages)
    @sent_messages = sent_messages
  end

  def send_message(chat_id:, text:, parse_mode: nil, disable_web_page_preview: nil)
    @sent_messages << {
      chat_id: chat_id,
      text: text,
      parse_mode: parse_mode,
      disable_web_page_preview: disable_web_page_preview
    }
    { ok: true, result: { message_id: rand(1000) } }
  end
end

# Mock message structure
class MockMessage
  attr_reader :chat, :from, :text

  def initialize(chat_id, text, username = 'testuser', first_name = 'Test')
    @chat = MockChat.new(chat_id)
    @from = MockUser.new(username, first_name)
    @text = text
  end
end

class MockChat
  attr_reader :id

  def initialize(id)
    @id = id
  end
end

class MockUser
  attr_reader :username, :first_name

  def initialize(username, first_name)
    @username = username
    @first_name = first_name
  end
end

class TestIntegration < Minitest::Test
  def setup
    super
    @bot = MockTelegramBot.new
    @chat_id = 12345
    @username = 'testuser'
    @first_name = 'Test User'

    # Setup mock API responses
    mock_ckpool_response('3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    mock_difficulty_response(25_000_000_000_000_000)
  end

  def process_message(text)
    message = MockMessage.new(@chat_id, text, @username, @first_name)
    process_telegram_message(message, @bot)
  end

  def last_message
    @bot.sent_messages.last
  end

  def all_messages
    @bot.sent_messages
  end

  # Simulate message processing logic from app.rb
  def process_telegram_message(message, bot)
    return unless message.text

    chat_id = message.chat.id
    text = message.text.strip
    username = message.from.username
    first_name = message.from.first_name

    # User creation/update
    user = User.find_or_create(chat_id, username: username, first_name: first_name)

    case text
    when '/start'
      user.update(active: true)
      user.log_command('start')

      welcome_msg = "👋 **CKPool Solo Mining Monitor Botへようこそ！**\n\n📋 **使用可能なコマンド:**"
      bot.api.send_message(chat_id: chat_id, text: welcome_msg, parse_mode: 'Markdown')

    when /^\/add_worker\s+(\S+)\s+(\S+)$/
      label, btc_address = $1, $2
      user.log_command('add_worker', "#{label} #{btc_address}")

      unless btc_address =~ /^(?:[13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[02-9ac-hj-np-z]{11,71})$/
        bot.api.send_message(chat_id: chat_id, text: "❌ 無効なBTCアドレスです。")
        return
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
        workers.each { |w| lines << "• #{w.label}: `#{w.btc_address}`" }
        msg = lines.join("\n")
      end

      bot.api.send_message(chat_id: chat_id, text: msg, parse_mode: 'Markdown')

    when '/check', '/now'
      user.log_command('check')

      workers = user.active_workers
      if workers.empty?
        bot.api.send_message(chat_id: chat_id, text: "❌ ワーカーが登録されていません。", parse_mode: 'Markdown')
        return
      end

      bot.api.send_message(chat_id: chat_id, text: "📊 データを取得中... (#{workers.size}ワーカー)")
      bot.api.send_message(chat_id: chat_id, text: "📈 **現在のマイニング状況**", parse_mode: 'Markdown')

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
      lines = ["📊 **現在の設定:**", "", "• 日次レポート: #{"%02d:%02d" % [user.hour, user.minute]} JST"]
      lines << "• 配信状態: #{user.active ? "有効 ✅" : "無効 ❌"}"
      lines << "• 登録ワーカー数: #{workers.size}"

      bot.api.send_message(chat_id: chat_id, text: lines.join("\n"), parse_mode: 'Markdown')

    when '/stop'
      user.log_command('stop')
      user.update(active: false)

      bot.api.send_message(chat_id: chat_id, text: "🔕 通知を停止しました。")

    when '/help'
      user.log_command('help')
      bot.api.send_message(chat_id: chat_id, text: "📋 **コマンド一覧:**", parse_mode: 'Markdown')

    else
      bot.api.send_message(chat_id: chat_id, text: "❓ 不明なコマンドです。", parse_mode: 'Markdown')
    end
  end

  def test_start_command
    process_message('/start')

    assert_equal 1, all_messages.size
    message = last_message

    assert_equal @chat_id, message[:chat_id]
    assert_includes message[:text], 'ようこそ'
    assert_includes message[:text], 'add_worker'
    assert_equal 'Markdown', message[:parse_mode]

    # Check user was created and logged
    user = User[@chat_id]
    refute_nil user
    assert user.active
    assert_equal 'testuser', user.username

    logs = CommandLog.where(chat_id: @chat_id).all
    assert_equal 1, logs.size
    assert_equal 'start', logs.first.command
  end

  def test_add_worker_valid_address
    process_message('/start')
    @bot.clear_messages

    process_message('/add_worker miner1 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')

    message = last_message
    assert_includes message[:text], '✅'
    assert_includes message[:text], 'miner1'
    assert_includes message[:text], '追加しました'

    # Check worker was created
    worker = Worker.find_by_label(@chat_id, 'miner1')
    refute_nil worker
    assert_equal '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy', worker.btc_address

    # Check command was logged
    logs = CommandLog.where(command: 'add_worker').all
    assert_equal 1, logs.size
    assert_includes logs.first.parameters, 'miner1'
  end

  def test_add_worker_invalid_address
    process_message('/start')
    @bot.clear_messages

    process_message('/add_worker miner1 invalid_address')

    message = last_message
    assert_includes message[:text], '❌'
    assert_includes message[:text], '無効'

    # Check worker was not created
    worker = Worker.find_by_label(@chat_id, 'miner1')
    assert_nil worker
  end

  def test_add_worker_update_existing
    process_message('/start')
    process_message('/add_worker miner1 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    @bot.clear_messages

    process_message('/add_worker miner1 3ABC123DEF456GHI789JKL012MNO345PQR678STU')

    message = last_message
    assert_includes message[:text], '✅'
    assert_includes message[:text], '更新しました'

    # Check worker was updated
    worker = Worker.find_by_label(@chat_id, 'miner1')
    assert_equal '3ABC123DEF456GHI789JKL012MNO345PQR678STU', worker.btc_address
  end

  def test_remove_worker_existing
    process_message('/start')
    process_message('/add_worker miner1 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    @bot.clear_messages

    process_message('/remove_worker miner1')

    message = last_message
    assert_includes message[:text], '✅'
    assert_includes message[:text], '削除しました'

    # Check worker was deleted
    worker = Worker.find_by_label(@chat_id, 'miner1')
    assert_nil worker
  end

  def test_remove_worker_nonexistent
    process_message('/start')
    @bot.clear_messages

    process_message('/remove_worker nonexistent')

    message = last_message
    assert_includes message[:text], '❌'
    assert_includes message[:text], '見つかりません'
  end

  def test_list_workers_empty
    process_message('/start')
    @bot.clear_messages

    process_message('/list_workers')

    message = last_message
    assert_includes message[:text], '登録されているワーカーはありません'
  end

  def test_list_workers_with_data
    process_message('/start')
    process_message('/add_worker miner1 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    process_message('/add_worker miner2 3ABC123DEF456GHI789JKL012MNO345PQR678STU')
    @bot.clear_messages

    process_message('/list_workers')

    message = last_message
    assert_includes message[:text], '登録ワーカー一覧'
    assert_includes message[:text], 'miner1'
    assert_includes message[:text], 'miner2'
    assert_includes message[:text], '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy'
  end

  def test_check_command_no_workers
    process_message('/start')
    @bot.clear_messages

    process_message('/check')

    message = last_message
    assert_includes message[:text], '❌'
    assert_includes message[:text], 'ワーカーが登録されていません'
  end

  def test_check_command_with_workers
    process_message('/start')
    process_message('/add_worker miner1 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    @bot.clear_messages

    process_message('/check')

    messages = all_messages
    assert_equal 2, messages.size

    assert_includes messages[0][:text], 'データを取得中'
    assert_includes messages[0][:text], '1ワーカー'

    assert_includes messages[1][:text], 'マイニング状況'
  end

  def test_now_command_alias
    process_message('/start')
    process_message('/add_worker miner1 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    @bot.clear_messages

    process_message('/now')

    # Should work the same as /check
    messages = all_messages
    assert_equal 2, messages.size
    assert_includes messages[0][:text], 'データを取得中'
  end

  def test_time_command_valid
    process_message('/start')
    @bot.clear_messages

    process_message('/time 14:30')

    message = last_message
    assert_includes message[:text], '✅'
    assert_includes message[:text], '14:30'

    # Check user settings were updated
    user = User[@chat_id]
    assert_equal 14, user.hour
    assert_equal 30, user.minute
    assert user.active
  end

  def test_time_command_invalid
    process_message('/start')
    @bot.clear_messages

    process_message('/time 25:70')

    message = last_message
    assert_includes message[:text], '❌'
    assert_includes message[:text], '無効'
  end

  def test_status_command
    process_message('/start')
    process_message('/time 15:45')
    process_message('/add_worker miner1 3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    @bot.clear_messages

    process_message('/status')

    message = last_message
    assert_includes message[:text], '現在の設定'
    assert_includes message[:text], '15:45'
    assert_includes message[:text], '有効 ✅'
    assert_includes message[:text], 'ワーカー数: 1'
    assert_includes message[:text], 'miner1'
  end

  def test_stop_command
    process_message('/start')
    @bot.clear_messages

    process_message('/stop')

    message = last_message
    assert_includes message[:text], '🔕'
    assert_includes message[:text], '停止'

    # Check user was deactivated
    user = User[@chat_id]
    refute user.active
  end

  def test_help_command
    process_message('/start')
    @bot.clear_messages

    process_message('/help')

    message = last_message
    assert_includes message[:text], 'コマンド一覧'
    assert_equal 'Markdown', message[:parse_mode]
  end

  def test_unknown_command
    process_message('/start')
    @bot.clear_messages

    process_message('/unknown')

    message = last_message
    assert_includes message[:text], '❓'
    assert_includes message[:text], '不明'
  end

  def test_command_logging
    process_message('/start')
    process_message('/help')
    process_message('/status')

    logs = CommandLog.where(chat_id: @chat_id).order(:executed_at).all
    assert_equal 3, logs.size

    commands = logs.map(&:command)
    assert_equal ['start', 'help', 'status'], commands
  end

  def test_user_activity_tracking
    process_message('/start')

    user = User[@chat_id]
    refute_nil user.last_active_at

    initial_time = user.last_active_at

    sleep 0.1  # Small delay

    process_message('/help')

    user.reload
    assert user.last_active_at > initial_time
  end
end