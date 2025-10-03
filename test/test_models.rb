require_relative 'test_helper'

class TestModels < Minitest::Test
  def test_user_creation
    user = User.create(
      chat_id: 12345,
      username: 'testuser',
      first_name: 'Test User'
    )

    assert_equal 12345, user.chat_id
    assert_equal 'testuser', user.username
    assert_equal 'Test User', user.first_name
    assert_equal 9, user.hour
    assert_equal 0, user.minute
    assert user.active
    refute_nil user.created_at
  end

  def test_user_find_or_create_new_user
    user = User.find_or_create(12345, username: 'newuser', first_name: 'New User')

    assert_equal 12345, user.chat_id
    assert_equal 'newuser', user.username
    assert_equal 'New User', user.first_name
    refute_nil user.last_active_at
  end

  def test_user_find_or_create_existing_user
    existing = create_test_user(12345, 'original', 'Original')

    user = User.find_or_create(12345, username: 'updated', first_name: 'Updated')

    assert_equal existing.id, user.id
    assert_equal 'updated', user.username
    assert_equal 'Updated', user.first_name
    refute_nil user.last_active_at
  end

  def test_user_active_workers
    user = create_test_user
    worker1 = create_test_worker(user, 'worker1', '3ABC123')
    worker2 = create_test_worker(user, 'worker2', '3DEF456')

    workers = user.active_workers
    assert_equal 2, workers.size
    assert_includes workers.map(&:label), 'worker1'
    assert_includes workers.map(&:label), 'worker2'
  end

  def test_user_log_command
    user = create_test_user

    user.log_command('test_command', 'param1 param2')

    logs = CommandLog.where(chat_id: user.chat_id).all
    assert_equal 1, logs.size
    assert_equal 'test_command', logs.first.command
    assert_equal 'param1 param2', logs.first.parameters
  end

  def test_worker_creation
    user = create_test_user
    worker = Worker.create(
      chat_id: user.chat_id,
      label: 'test_worker',
      btc_address: '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy'
    )

    assert_equal user.chat_id, worker.chat_id
    assert_equal 'test_worker', worker.label
    assert_equal '3LKSkoE3QtXAU6oDmVHdMmEJ3EwwS6ESwy', worker.btc_address
    refute_nil worker.created_at
  end

  def test_worker_unique_constraint
    user = create_test_user
    Worker.create(chat_id: user.chat_id, label: 'worker1', btc_address: '3ABC123')

    assert_raises(Sequel::UniqueConstraintViolation) do
      Worker.create(chat_id: user.chat_id, label: 'worker1', btc_address: '3DEF456')
    end
  end

  def test_worker_find_by_label
    user = create_test_user
    worker = create_test_worker(user, 'test_label', '3ABC123')

    found = Worker.find_by_label(user.chat_id, 'test_label')
    assert_equal worker.id, found.id

    not_found = Worker.find_by_label(user.chat_id, 'nonexistent')
    assert_nil not_found
  end

  def test_worker_should_notify_hit_new_bestshare
    user = create_test_user
    worker = create_test_worker(user)

    result = worker.should_notify_hit?(1000.0)
    assert result

    # Check that hit state was created and updated
    hit_state = worker.hit_state
    refute_nil hit_state
    assert_equal 1000.0, hit_state.last_notified_bestshare
    refute_nil hit_state.last_hit_at
  end

  def test_worker_should_notify_hit_duplicate_bestshare
    user = create_test_user
    worker = create_test_worker(user)

    # First hit
    assert worker.should_notify_hit?(1000.0)

    # Same bestshare - should not notify
    refute worker.should_notify_hit?(1000.0)

    # Lower bestshare - should not notify
    refute worker.should_notify_hit?(999.0)

    # Higher bestshare - should notify
    assert worker.should_notify_hit?(1001.0)
  end

  def test_hit_state_creation
    user = create_test_user
    worker = create_test_worker(user)

    hit_state = HitState.create(
      worker_id: worker.id,
      last_notified_bestshare: 500.0,
      last_hit_at: Time.now
    )

    assert_equal worker.id, hit_state.worker_id
    assert_equal 500.0, hit_state.last_notified_bestshare
    refute_nil hit_state.last_hit_at
  end

  def test_command_log_creation
    user = create_test_user

    log = CommandLog.create(
      chat_id: user.chat_id,
      command: 'test_command',
      parameters: 'test params',
      executed_at: Time.now
    )

    assert_equal user.chat_id, log.chat_id
    assert_equal 'test_command', log.command
    assert_equal 'test params', log.parameters
    refute_nil log.executed_at
  end

  def test_command_log_recent_activity
    user = create_test_user

    # Create logs at different times
    old_log = CommandLog.create(
      chat_id: user.chat_id,
      command: 'old_command',
      executed_at: Time.now - 25 * 3600  # 25 hours ago
    )

    recent_log = CommandLog.create(
      chat_id: user.chat_id,
      command: 'recent_command',
      executed_at: Time.now - 1 * 3600   # 1 hour ago
    )

    recent_logs = CommandLog.recent_activity(24).all
    assert_equal 1, recent_logs.size
    assert_equal 'recent_command', recent_logs.first.command
  end

  def test_command_log_active_users
    user1 = create_test_user(12345)
    user2 = create_test_user(67890)

    # User1: 3 commands
    3.times do |i|
      CommandLog.create(chat_id: user1.chat_id, command: "cmd#{i}", executed_at: Time.now)
    end

    # User2: 1 command
    CommandLog.create(chat_id: user2.chat_id, command: 'cmd', executed_at: Time.now)

    active = CommandLog.active_users.all
    assert_equal 2, active.size

    # Should be ordered by command count (descending)
    assert_equal user1.chat_id, active.first[:chat_id]
    assert_equal 3, active.first[:command_count]
    assert_equal user2.chat_id, active.last[:chat_id]
    assert_equal 1, active.last[:command_count]
  end

  def test_command_log_popular_commands
    user = create_test_user

    # Create different commands with different frequencies
    3.times { CommandLog.create(chat_id: user.chat_id, command: 'check', executed_at: Time.now) }
    2.times { CommandLog.create(chat_id: user.chat_id, command: 'status', executed_at: Time.now) }
    1.times { CommandLog.create(chat_id: user.chat_id, command: 'help', executed_at: Time.now) }

    popular = CommandLog.popular_commands.all
    assert_equal 3, popular.size

    # Should be ordered by usage count (descending)
    assert_equal 'check', popular.first[:command]
    assert_equal 3, popular.first[:usage_count]
    assert_equal 'status', popular[1][:command]
    assert_equal 2, popular[1][:usage_count]
    assert_equal 'help', popular.last[:command]
    assert_equal 1, popular.last[:usage_count]
  end

  def test_cascade_delete_workers_when_user_deleted
    user = create_test_user
    worker = create_test_worker(user)
    worker_id = worker.id

    user.destroy

    # Worker should be deleted due to cascade
    assert_nil Worker[worker_id]
  end

  def test_cascade_delete_hit_state_when_worker_deleted
    user = create_test_user
    worker = create_test_worker(user)

    # Create hit state
    hit_state = HitState.create(worker_id: worker.id, last_notified_bestshare: 100.0)

    worker.destroy

    # Hit state should be deleted due to cascade
    refute HitState.where(worker_id: worker.id).first
  end
end