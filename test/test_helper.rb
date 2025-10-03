require 'minitest/autorun'
require 'minitest/reporters'
require 'webmock/minitest'
require 'dotenv/load'

# Use a test database
ENV['DATABASE_URL'] = nil  # Force SQLite usage
ENV['TEST_ENV'] = 'true'

# Load our application
require_relative '../db'

# Configure minitest reporters
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

class Minitest::Test
  def setup
    # Clean database before each test
    DB.transaction do
      DB[:command_logs].delete
      DB[:hit_states].delete
      DB[:workers].delete
      DB[:users].delete
    end
  end

  def teardown
    # Clean up after each test
    WebMock.reset!
  end

  # Helper method to create a test user
  def create_test_user(chat_id = 12345, username = 'testuser', first_name = 'Test')
    User.create(
      chat_id: chat_id,
      username: username,
      first_name: first_name,
      hour: 9,
      minute: 0,
      active: true
    )
  end

  # Helper method to create a test worker
  def create_test_worker(user, label = 'test_worker', btc_address = '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    Worker.create(
      chat_id: user.chat_id,
      label: label,
      btc_address: btc_address
    )
  end

  # Mock CKPool API response
  def mock_ckpool_response(address, data = nil)
    data ||= {
      "hashrate1m" => "1234567890",
      "hashrate5m" => "1234567890",
      "hashrate1hr" => "1234567890",
      "hashrate1d" => "1234567890",
      "hashrate7d" => "1234567890",
      "shares" => 100,
      "bestshare" => "123456789012345",
      "bestever" => "123456789012345",
      "lastshare" => 1633024800,
      "authorised" => 1633024800
    }

    stub_request(:get, "https://solo.ckpool.org/users/#{address}")
      .to_return(
        status: 200,
        body: data.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  # Mock difficulty API response
  def mock_difficulty_response(difficulty = 1000000000000)
    stub_request(:get, "https://blockchain.info/q/getdifficulty")
      .to_return(
        status: 200,
        body: difficulty.to_s,
        headers: { 'Content-Type' => 'text/plain' }
      )
  end
end