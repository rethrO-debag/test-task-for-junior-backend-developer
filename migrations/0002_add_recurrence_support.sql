ALTER TABLE tasks 
ADD COLUMN recurrence JSONB,
ADD COLUMN parent_id BIGINT REFERENCES tasks(id) ON DELETE CASCADE,
ADD COLUMN occurrence_date TIMESTAMPTZ;

CREATE INDEX idx_tasks_parent_id ON tasks(parent_id);
CREATE INDEX idx_tasks_occurrence_date ON tasks(occurrence_date) WHERE occurrence_date IS NOT NULL;
CREATE INDEX idx_tasks_parent_occurrence ON tasks(parent_id, occurrence_date);