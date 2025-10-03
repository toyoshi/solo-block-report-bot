require 'rake/testtask'

# Default task
task default: :test

# Test task
Rake::TestTask.new do |t|
  t.libs << 'test'
  t.pattern = 'test/test_*.rb'
  t.verbose = true
end

# Individual test tasks
namespace :test do
  desc "Run model tests"
  Rake::TestTask.new(:models) do |t|
    t.libs << 'test'
    t.pattern = 'test/test_models.rb'
    t.verbose = true
  end

  desc "Run utility function tests"
  Rake::TestTask.new(:utils) do |t|
    t.libs << 'test'
    t.pattern = 'test/test_utils.rb'
    t.verbose = true
  end

  desc "Run integration tests"
  Rake::TestTask.new(:integration) do |t|
    t.libs << 'test'
    t.pattern = 'test/test_integration.rb'
    t.verbose = true
  end
end

# Development tasks
namespace :dev do
  desc "Start bot in development mode"
  task :start do
    exec "ruby app.rb"
  end

  desc "Start bot with Docker"
  task :docker do
    exec "docker-compose up --build"
  end

  desc "Check database status"
  task :db_status do
    require_relative 'db'
    puts "Database adapter: #{DB.adapter_scheme}"
    puts "Database file: #{DB.opts[:database] || 'in-memory'}"
    puts "Tables:"
    DB.tables.each do |table|
      count = DB[table].count
      puts "  #{table}: #{count} records"
    end
  end

  desc "Reset database (WARNING: deletes all data)"
  task :db_reset do
    require_relative 'db'
    puts "Resetting database..."

    DB.transaction do
      [:command_logs, :hit_states, :workers, :users].each do |table|
        count = DB[table].count
        DB[table].delete
        puts "Deleted #{count} records from #{table}"
      end
    end

    puts "Database reset complete"
  end
end

# Utility tasks
namespace :utils do
  desc "Validate BTC address"
  task :validate_btc, [:address] do |t, args|
    require_relative 'app'

    address = args[:address]
    if address.nil?
      puts "Usage: rake utils:validate_btc[3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy]"
      exit 1
    end

    if valid_btc_address?(address)
      puts "✅ Valid BTC address: #{address}"
    else
      puts "❌ Invalid BTC address: #{address}"
    end
  end

  desc "Test API connections"
  task :test_apis do
    require_relative 'app'

    puts "Testing CKPool API..."
    test_address = '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy'
    data = fetch_ckpool_data(test_address)

    if data
      puts "✅ CKPool API working"
      puts "  Hashrate 1m: #{format_number(data['hashrate1m'])}H/s"
      puts "  Shares: #{data['shares']}"
      puts "  Best share: #{format_number(data['bestshare'])}"
    else
      puts "❌ CKPool API failed"
    end

    puts "\nTesting Difficulty API..."
    difficulty = fetch_network_difficulty

    if difficulty
      puts "✅ Difficulty API working"
      puts "  Network difficulty: #{format_number(difficulty)}"
    else
      puts "❌ Difficulty API failed"
    end
  end
end