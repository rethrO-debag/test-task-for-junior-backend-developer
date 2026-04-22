package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	taskdomain "example.com/taskservice/internal/domain/task"
)

type Repository struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, task *taskdomain.Task) (*taskdomain.Task, error) {
	query := `
		INSERT INTO tasks (title, description, status, recurrence, parent_id, occurrence_date, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id, title, description, status, recurrence, parent_id, occurrence_date, created_at, updated_at
	`

	var recurrenceJSON []byte
	if task.Recurrence != nil {
		recurrenceJSON, _ = json.Marshal(task.Recurrence)
	}

	row := r.pool.QueryRow(ctx, query,
		task.Title,
		task.Description,
		task.Status,
		recurrenceJSON,
		task.ParentID,
		task.OccurrenceDate,
		task.CreatedAt,
		task.UpdatedAt,
	)

	created, err := r.scanTask(row)
	if err != nil {
		return nil, err
	}

	return created, nil
}

func (r *Repository) GetByID(ctx context.Context, id int64) (*taskdomain.Task, error) {
	query := `
		SELECT id, title, description, status, recurrence, parent_id, occurrence_date, created_at, updated_at
		FROM tasks
		WHERE id = $1
	`

	row := r.pool.QueryRow(ctx, query, id)
	task, err := r.scanTask(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, taskdomain.ErrNotFound
		}
		return nil, err
	}

	return task, nil
}

func (r *Repository) Update(ctx context.Context, task *taskdomain.Task) (*taskdomain.Task, error) {
	query := `
		UPDATE tasks
		SET title = $1,
			description = $2,
			status = $3,
			recurrence = $4,
			updated_at = $5
		WHERE id = $6
		RETURNING id, title, description, status, recurrence, parent_id, occurrence_date, created_at, updated_at
	`

	var recurrenceJSON []byte
	if task.Recurrence != nil {
		recurrenceJSON, _ = json.Marshal(task.Recurrence)
	}

	row := r.pool.QueryRow(ctx, query,
		task.Title,
		task.Description,
		task.Status,
		recurrenceJSON,
		task.UpdatedAt,
		task.ID,
	)

	updated, err := r.scanTask(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, taskdomain.ErrNotFound
		}
		return nil, err
	}

	return updated, nil
}

func (r *Repository) Delete(ctx context.Context, id int64) error {
	query := `DELETE FROM tasks WHERE id = $1`

	result, err := r.pool.Exec(ctx, query, id)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return taskdomain.ErrNotFound
	}

	return nil
}

func (r *Repository) List(ctx context.Context) ([]taskdomain.Task, error) {
	query := `
		SELECT id, title, description, status, recurrence, parent_id, occurrence_date, created_at, updated_at
		FROM tasks
		ORDER BY id DESC
	`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	tasks := make([]taskdomain.Task, 0)
	for rows.Next() {
		task, err := r.scanTask(rows)
		if err != nil {
			return nil, err
		}
		tasks = append(tasks, *task)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return tasks, nil
}

func (r *Repository) ListByParent(ctx context.Context, parentID int64) ([]taskdomain.Task, error) {
	query := `
		SELECT id, title, description, status, recurrence, parent_id, occurrence_date, created_at, updated_at
		FROM tasks
		WHERE parent_id = $1
		ORDER BY occurrence_date ASC
	`

	rows, err := r.pool.Query(ctx, query, parentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	tasks := make([]taskdomain.Task, 0)
	for rows.Next() {
		task, err := r.scanTask(rows)
		if err != nil {
			return nil, err
		}
		tasks = append(tasks, *task)
	}

	return tasks, nil
}

func (r *Repository) GetPendingOccurrences(ctx context.Context, before time.Time) ([]taskdomain.Task, error) {
	query := `
		SELECT id, title, description, status, recurrence, parent_id, occurrence_date, created_at, updated_at
		FROM tasks
		WHERE parent_id IS NOT NULL 
		  AND status = $1
		  AND occurrence_date <= $2
		ORDER BY occurrence_date ASC
	`

	rows, err := r.pool.Query(ctx, query, taskdomain.StatusNew, before)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	tasks := make([]taskdomain.Task, 0)
	for rows.Next() {
		task, err := r.scanTask(rows)
		if err != nil {
			return nil, err
		}
		tasks = append(tasks, *task)
	}

	return tasks, nil
}

type taskScanner interface {
	Scan(dest ...any) error
}

// ИСПРАВЛЕННЫЙ scanTask - добавлены parent_id и occurrence_date
func (r *Repository) scanTask(scanner taskScanner) (*taskdomain.Task, error) {
	var (
		task           taskdomain.Task
		status         string
		recurrenceJSON []byte
		parentID       *int64
		occurrenceDate *time.Time
	)

	if err := scanner.Scan(
		&task.ID,
		&task.Title,
		&task.Description,
		&status,
		&recurrenceJSON,
		&parentID,
		&occurrenceDate,
		&task.CreatedAt,
		&task.UpdatedAt,
	); err != nil {
		return nil, err
	}

	task.Status = taskdomain.Status(status)
	task.ParentID = parentID
	task.OccurrenceDate = occurrenceDate

	if len(recurrenceJSON) > 0 {
		var recurrence taskdomain.RecurrenceConfig
		if err := json.Unmarshal(recurrenceJSON, &recurrence); err != nil {
			return nil, err
		}
		task.Recurrence = &recurrence
	}

	return &task, nil
}
