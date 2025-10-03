require 'sequel'
require 'time'

# データベース接続
# 本番環境ではDATABASE_URLを使用、ローカルではSQLiteを使用
DB = if ENV['DATABASE_URL']
  Sequel.connect(ENV['DATABASE_URL'])
else
  Sequel.sqlite('bot.db')
end

# テーブル作成順序と外部キー制約を正しく設定
DB.create_table? :users do
  column :chat_id, :bigint, primary_key: true
  String :username
  String :first_name
  Integer :hour, default: 9
  Integer :minute, default: 0
  TrueClass :active, default: true
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :last_active_at
end

DB.create_table? :workers do
  primary_key :id
  column :chat_id, :bigint, null: false
  String :label, null: false, size: 100
  String :btc_address, null: false, size: 100
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

  foreign_key [:chat_id], :users, key: [:chat_id], on_delete: :cascade
  unique [:chat_id, :label]
  index :chat_id
  index :btc_address
end

DB.create_table? :hit_states do
  foreign_key :worker_id, :workers, type: :integer, on_delete: :cascade
  Float :last_notified_bestshare, default: 0.0
  DateTime :last_hit_at

  primary_key [:worker_id]
end

DB.create_table? :command_logs do
  primary_key :id
  column :chat_id, :bigint, null: false
  String :command, null: false, size: 50
  String :parameters, size: 255
  DateTime :executed_at, default: Sequel::CURRENT_TIMESTAMP

  foreign_key [:chat_id], :users, key: [:chat_id], on_delete: :cascade
  index :chat_id
  index :executed_at
  index :command
  index [:chat_id, :executed_at]
end

# Sequelモデル定義
class User < Sequel::Model
  one_to_many :workers, key: :chat_id
  one_to_many :command_logs, key: :chat_id

  # Enable unrestricted primary key assignment
  unrestrict_primary_key

  def self.find_or_create(chat_id, username: nil, first_name: nil)
    user = self[chat_id]
    if user
      user.update(
        last_active_at: Time.now,
        username: username || user.username,
        first_name: first_name || user.first_name
      )
      user
    else
      self.create(
        chat_id: chat_id,
        username: username,
        first_name: first_name,
        last_active_at: Time.now
      )
    end
  end

  def active_workers
    workers_dataset.all
  end

  def log_command(command, parameters = nil)
    CommandLog.create(
      chat_id: self.chat_id,
      command: command,
      parameters: parameters,
      executed_at: Time.now
    )
  end
end

class Worker < Sequel::Model
  many_to_one :user, key: :chat_id, primary_key: :chat_id
  one_to_one :hit_state

  def self.find_by_label(chat_id, label)
    self.first(chat_id: chat_id, label: label)
  end

  def get_or_create_hit_state
    hit_state || begin
      new_state = HitState.create(worker_id: self.id)
      associations[:hit_state] = new_state
      new_state
    end
  end

  def should_notify_hit?(bestshare)
    state = get_or_create_hit_state
    if bestshare > state.last_notified_bestshare
      state.update(
        last_notified_bestshare: bestshare,
        last_hit_at: Time.now
      )
      true
    else
      false
    end
  end
end

class HitState < Sequel::Model
  many_to_one :worker

  # Enable unrestricted primary key assignment
  unrestrict_primary_key
end

class CommandLog < Sequel::Model
  many_to_one :user, key: :chat_id, primary_key: :chat_id

  # 分析用メソッド
  def self.recent_activity(hours = 24)
    where(executed_at: (Time.now - hours * 3600)..Time.now)
  end

  def self.active_users(hours = 24)
    recent_activity(hours)
      .select_group(:chat_id)
      .select_append{count(:id).as(:command_count)}
      .order(Sequel.desc(:command_count))
  end

  def self.popular_commands(hours = 24)
    recent_activity(hours)
      .select_group(:command)
      .select_append{count(:id).as(:usage_count)}
      .order(Sequel.desc(:usage_count))
  end

  def self.hourly_distribution(hours = 24)
    recent_activity(hours)
      .select{strftime('%H', executed_at).as(:hour)}
      .select_append{count(:id).as(:count)}
      .group_by(:hour)
      .order(:hour)
  end
end

begin
  # Test database connection
  DB.test_connection
  puts "Database connection successful"
  puts "SQLite database file: #{DB.opts[:database] || 'in-memory'}" if DB.adapter_scheme == :sqlite
rescue => e
  puts "Database connection failed: #{e.message}"
  puts "Error class: #{e.class}"
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

puts "Database initialized successfully"