DROP INDEX IF EXISTS idx_tasks_parent_occurrence;
DROP INDEX IF EXISTS idx_tasks_occurrence_date;
DROP INDEX IF EXISTS idx_tasks_parent_id;

ALTER TABLE tasks 
DROP COLUMN IF EXISTS recurrence,
DROP COLUMN IF EXISTS parent_id,
DROP COLUMN IF EXISTS occurrence_date;