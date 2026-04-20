CREATE TABLE IF NOT EXISTS tasks (
  id VARCHAR(64) PRIMARY KEY,
  owner_key VARCHAR(32) NOT NULL,
  is_family TINYINT(1) NOT NULL DEFAULT 0,
  title VARCHAR(255) NOT NULL,
  details TEXT NOT NULL,
  due_date VARCHAR(16) NOT NULL DEFAULT '',
  time_value VARCHAR(16) NOT NULL DEFAULT '',
  workflow_status VARCHAR(32) NOT NULL DEFAULT 'todo',
  priority VARCHAR(32) NOT NULL DEFAULT 'medium',
  tags_json JSON NOT NULL,
  participants_json JSON NOT NULL,
  duration_minutes INT NOT NULL DEFAULT 0,
  updated_at VARCHAR(32) NOT NULL,
  version INT NOT NULL DEFAULT 1,
  INDEX idx_tasks_updated_at (updated_at),
  INDEX idx_tasks_owner (owner_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS family_tasks (
  id VARCHAR(64) PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  details TEXT NOT NULL,
  due_date VARCHAR(16) NOT NULL DEFAULT '',
  time_value VARCHAR(16) NOT NULL DEFAULT '',
  workflow_status VARCHAR(32) NOT NULL DEFAULT 'todo',
  participants_json JSON NOT NULL,
  duration_minutes INT NOT NULL DEFAULT 0,
  updated_at VARCHAR(32) NOT NULL,
  version INT NOT NULL DEFAULT 1,
  INDEX idx_family_tasks_updated_at (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sync_events (
  event_id VARCHAR(128) PRIMARY KEY,
  source VARCHAR(32) NOT NULL,
  created_at VARCHAR(32) NOT NULL,
  INDEX idx_sync_events_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS telegram_outbox (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  event_id VARCHAR(128) NOT NULL,
  payload_json JSON NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  retry_count INT NOT NULL DEFAULT 0,
  next_retry_at VARCHAR(32) NOT NULL,
  created_at VARCHAR(32) NOT NULL,
  updated_at VARCHAR(32) NOT NULL,
  UNIQUE KEY uq_telegram_outbox_event (event_id),
  INDEX idx_telegram_outbox_status_next (status, next_retry_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

