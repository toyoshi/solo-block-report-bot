#!/usr/bin/env ruby

# Test runner for CKPool Monitor Bot
require 'minitest/autorun'

# Set test environment
ENV['TEST_ENV'] = 'true'

# Load all test files
test_files = Dir[File.join(__dir__, 'test', 'test_*.rb')]

puts "Running tests..."
puts "Test files found: #{test_files.size}"

test_files.each do |file|
  puts "Loading: #{File.basename(file)}"
  require file
end

puts "\nRunning all tests..."