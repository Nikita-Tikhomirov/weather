ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS collaboration_json JSON NULL AFTER participants_json;

ALTER TABLE family_tasks
  ADD COLUMN IF NOT EXISTS collaboration_json JSON NULL AFTER participants_json;
