-- PostgreSQL/SQLite互換スキーマ
-- このファイルは参照用です（実際のテーブル作成はdb.rbで行われます）

-- ユーザー管理テーブル
CREATE TABLE IF NOT EXISTS users (
  chat_id      BIGINT PRIMARY KEY,
  username     VARCHAR(255),
  first_name   VARCHAR(255),
  hour         INTEGER DEFAULT 9,
  minute       INTEGER DEFAULT 0,
  active       BOOLEAN DEFAULT TRUE,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_active_at TIMESTAMP
);

-- ワーカー（BTCアドレス）管理テーブル
CREATE TABLE IF NOT EXISTS workers (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_id      BIGINT NOT NULL REFERENCES users(chat_id) ON DELETE CASCADE,
  label        VARCHAR(100) NOT NULL,
  btc_address  VARCHAR(100) NOT NULL,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(chat_id, label)
);

-- ブロック発見通知の重複防止用状態管理
CREATE TABLE IF NOT EXISTS hit_states (
  worker_id               INTEGER PRIMARY KEY REFERENCES workers(id) ON DELETE CASCADE,
  last_notified_bestshare REAL DEFAULT 0.0,
  last_hit_at             TIMESTAMP
);

-- コマンド実行ログ（アクティビティ分析用）
CREATE TABLE IF NOT EXISTS command_logs (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_id      BIGINT NOT NULL REFERENCES users(chat_id) ON DELETE CASCADE,
  command      VARCHAR(50) NOT NULL,
  parameters   VARCHAR(255),
  executed_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- インデックス（パフォーマンス向上）
CREATE INDEX idx_workers_chat_id ON workers(chat_id);
CREATE INDEX idx_workers_btc_address ON workers(btc_address);
CREATE INDEX idx_command_logs_chat_id ON command_logs(chat_id);
CREATE INDEX idx_command_logs_executed_at ON command_logs(executed_at);
CREATE INDEX idx_command_logs_command ON command_logs(command);
CREATE INDEX idx_command_logs_chat_executed ON command_logs(chat_id, executed_at);

-- PostgreSQL用のupdated_at自動更新トリガー（参考）
-- CREATE OR REPLACE FUNCTION update_updated_at_column()
-- RETURNS TRIGGER AS $$
-- BEGIN
--     NEW.updated_at = NOW();
--     RETURN NEW;
-- END;
-- $$ language 'plpgsql';
--
-- CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
--   FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
--
-- CREATE TRIGGER update_workers_updated_at BEFORE UPDATE ON workers
--   FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();