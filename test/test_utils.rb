require_relative 'test_helper'

# Load utility functions directly
require 'httparty'
require 'json'
require 'time'

# Import utility functions from app.rb
def valid_btc_address?(addr)
  !!(addr =~ /^(?:[13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[02-9ac-hj-np-z]{11,71})$/)
end

def format_timestamp(timestamp)
  return "N/A" if timestamp.nil? || timestamp == 0
  Time.at(timestamp).getlocal("+09:00").strftime("%Y-%m-%d %H:%M:%S JST")
end

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

def fetch_ckpool_data(address)
  url = "https://solo.ckpool.org/users/#{address}"
  response = HTTParty.get(url, timeout: 20)

  if response.code == 200
    JSON.parse(response.body)
  else
    raise "CKPool API error: #{response.code}"
  end
rescue => e
  nil
end

def fetch_network_difficulty
  url = "https://blockchain.info/q/getdifficulty"
  response = HTTParty.get(url, timeout: 10)

  if response.code == 200
    response.body.strip.to_f
  else
    raise "Blockchain.info API error: #{response.code}"
  end
rescue => e
  nil
end

def generate_worker_report(worker, data, difficulty)
  return nil if data.nil?

  bestshare = (data["bestshare"] || 0).to_f
  hit_status = if difficulty && bestshare >= difficulty
    "🎉 ブロック発見！ 🎉"
  elsif difficulty && bestshare > 0
    progress = (bestshare / difficulty * 100).round(4)
    "📊 進捗: #{progress}%"
  else
    "📊 進捗: 0%"
  end

  lines = []
  lines << "📍 #{worker.label}"
  lines << "アドレス: #{worker.btc_address}"
  lines << ""
  lines << "⚡ ハッシュレート:"
  lines << "• 1m: #{format_number(data["hashrate1m"])}H/s"
  lines << ""
  lines << "📊 シェア: #{data["shares"] || 0}"
  lines << "📊 ベストシェア: #{format_number(bestshare)}"
  lines << hit_status
  lines << ""
  lines << "🕐 最終シェア: #{format_timestamp(data["lastshare"])}"

  lines.join("\n")
end

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
    assert_equal '0.0', format_number('0')
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