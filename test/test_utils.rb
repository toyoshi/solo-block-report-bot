require_relative 'test_helper'

# Load utility functions from app.rb without running the bot
class UtilsExtractor
  class << self
    def extract_methods
      app_content = File.read(File.join(__dir__, '..', 'app.rb'))

      # Extract method definitions
      method_defs = app_content.scan(/^def\s+(\w+).*?^end/m)

      # Evaluate the methods in our context
      eval(app_content.gsub(/^Telegram::Bot::Client\.run.*$/m, ''))
    rescue => e
      # Fallback: define essential methods manually for testing
      define_fallback_methods
    end

    private

    def define_fallback_methods
      # Define utility methods for testing
    end
  end
end

# Extract utility methods
UtilsExtractor.extract_methods

class TestUtils < Minitest::Test
  def test_valid_btc_address_legacy
    # Valid legacy addresses (P2PKH)
    assert valid_btc_address?('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')
    assert valid_btc_address?('1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2')

    # Valid legacy addresses (P2SH)
    assert valid_btc_address?('3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')
    assert valid_btc_address?('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy')
  end

  def test_valid_btc_address_bech32
    # Valid bech32 addresses
    assert valid_btc_address?('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4')
    assert valid_btc_address?('bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3')
  end

  def test_invalid_btc_address
    # Invalid addresses
    refute valid_btc_address?('invalid_address')
    refute valid_btc_address?('')
    refute valid_btc_address?('1234')
    refute valid_btc_address?('xyz123')
    refute valid_btc_address?('bc1invalid')
    refute valid_btc_address?('2LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')  # Invalid prefix
  end

  def test_format_timestamp_valid
    timestamp = 1633024800  # Oct 1, 2021 00:00:00 UTC
    result = format_timestamp(timestamp)

    assert_includes result, '2021-10-01'
    assert_includes result, 'JST'
  end

  def test_format_timestamp_invalid
    assert_equal 'N/A', format_timestamp(nil)
    assert_equal 'N/A', format_timestamp(0)
  end

  def test_format_number_zeros
    assert_equal '0', format_number(nil)
    assert_equal '0', format_number(0)
    assert_equal '0', format_number('0')
  end

  def test_format_number_small_values
    assert_equal '123', format_number(123)
    assert_equal '999', format_number(999)
  end

  def test_format_number_kilo
    assert_equal '1.00 K', format_number(1000)
    assert_equal '1.50 K', format_number(1500)
    assert_equal '999.99 K', format_number(999990)
  end

  def test_format_number_mega
    assert_equal '1.00 M', format_number(1_000_000)
    assert_equal '2.50 M', format_number(2_500_000)
    assert_equal '999.99 M', format_number(999_990_000)
  end

  def test_format_number_giga
    assert_equal '1.00 G', format_number(1_000_000_000)
    assert_equal '3.14 G', format_number(3_140_000_000)
    assert_equal '999.99 G', format_number(999_990_000_000)
  end

  def test_format_number_tera
    assert_equal '1.00 T', format_number(1_000_000_000_000)
    assert_equal '5.67 T', format_number(5_670_000_000_000)
    assert_equal '999.99 T', format_number(999_990_000_000_000)
  end

  def test_format_number_peta
    assert_equal '1.00 P', format_number(1_000_000_000_000_000)
    assert_equal '2.34 P', format_number(2_340_000_000_000_000)
    assert_equal '10.50 P', format_number(10_500_000_000_000_000)
  end

  def test_format_number_string_input
    assert_equal '1.50 K', format_number('1500')
    assert_equal '2.00 M', format_number('2000000')
    assert_equal '3.00 G', format_number('3000000000')
  end

  def test_fetch_ckpool_data_success
    address = '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy'
    expected_data = {
      'hashrate1m' => '1000000000',
      'shares' => 100,
      'bestshare' => '500000000000'
    }

    mock_ckpool_response(address, expected_data)

    result = fetch_ckpool_data(address)
    assert_equal expected_data, result
  end

  def test_fetch_ckpool_data_failure
    address = '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy'

    stub_request(:get, "https://solo.ckpool.org/users/#{address}")
      .to_return(status: 500, body: 'Internal Server Error')

    result = fetch_ckpool_data(address)
    assert_nil result
  end

  def test_fetch_network_difficulty_success
    expected_difficulty = 25_000_000_000_000

    mock_difficulty_response(expected_difficulty)

    result = fetch_network_difficulty
    assert_equal expected_difficulty.to_f, result
  end

  def test_fetch_network_difficulty_failure
    stub_request(:get, "https://blockchain.info/q/getdifficulty")
      .to_return(status: 404, body: 'Not Found')

    result = fetch_network_difficulty
    assert_nil result
  end

  def test_generate_worker_report_success
    user = create_test_user
    worker = create_test_worker(user, 'test_miner', '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy')

    data = {
      'hashrate1m' => '1000000000',
      'hashrate5m' => '1100000000',
      'hashrate1hr' => '1200000000',
      'hashrate1d' => '1300000000',
      'hashrate7d' => '1400000000',
      'shares' => 150,
      'bestshare' => '5000000000000000',
      'bestever' => '6000000000000000',
      'lastshare' => 1633024800,
      'authorised' => 1633024800
    }

    difficulty = 25_000_000_000_000_000

    result = generate_worker_report(worker, data, difficulty)

    refute_nil result
    assert_includes result, 'test_miner'
    assert_includes result, '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy'
    assert_includes result, '1.00 G'  # hashrate formatting
    assert_includes result, '150'     # shares
    assert_includes result, '5.00 P'  # bestshare formatting
    assert_includes result, '2021-10-01'  # timestamp formatting
    assert_includes result, '進捗:'    # Progress indication
  end

  def test_generate_worker_report_block_found
    user = create_test_user
    worker = create_test_worker(user)

    data = {
      'hashrate1m' => '1000000000',
      'bestshare' => '30000000000000000',  # Higher than difficulty
      'shares' => 100,
      'lastshare' => 1633024800
    }

    difficulty = 25_000_000_000_000_000  # Lower than bestshare

    result = generate_worker_report(worker, data, difficulty)

    assert_includes result, 'ブロック発見'
  end

  def test_generate_worker_report_nil_data
    user = create_test_user
    worker = create_test_worker(user)

    result = generate_worker_report(worker, nil, 1000)
    assert_nil result
  end
end