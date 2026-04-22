package handlers

import (
	"time"

	taskdomain "example.com/taskservice/internal/domain/task"
)

type recurrenceConfigDTO struct {
	Type          string   `json:"type"`
	Interval      *int     `json:"interval,omitempty"`
	MonthDays     []int    `json:"month_days,omitempty"`
	SpecificDates []string `json:"specific_dates,omitempty"`
	Parity        *string  `json:"parity,omitempty"`
	StartDate     string   `json:"start_date"`
	EndDate       *string  `json:"end_date,omitempty"`
}

type taskMutationDTO struct {
	Title       string               `json:"title"`
	Description string               `json:"description"`
	Status      taskdomain.Status    `json:"status"`
	Recurrence  *recurrenceConfigDTO `json:"recurrence,omitempty"`
}

type taskDTO struct {
	ID             int64                `json:"id"`
	Title          string               `json:"title"`
	Description    string               `json:"description"`
	Status         taskdomain.Status    `json:"status"`
	Recurrence     *recurrenceConfigDTO `json:"recurrence,omitempty"`
	ParentID       *int64               `json:"parent_id,omitempty"`       // <- ДОБАВИТЬ
	OccurrenceDate *string              `json:"occurrence_date,omitempty"` // <- ДОБАВИТЬ
	CreatedAt      time.Time            `json:"created_at"`
	UpdatedAt      time.Time            `json:"updated_at"`
}

func newTaskDTO(task *taskdomain.Task) taskDTO {
	dto := taskDTO{
		ID:          task.ID,
		Title:       task.Title,
		Description: task.Description,
		Status:      task.Status,
		ParentID:    task.ParentID, // <- ДОБАВИТЬ
		CreatedAt:   task.CreatedAt,
		UpdatedAt:   task.UpdatedAt,
	}

	if task.OccurrenceDate != nil {
		dateStr := task.OccurrenceDate.Format(time.RFC3339)
		dto.OccurrenceDate = &dateStr
	}

	if task.Recurrence != nil {
		dto.Recurrence = &recurrenceConfigDTO{
			Type:      string(task.Recurrence.Type),
			Interval:  task.Recurrence.Interval,
			MonthDays: task.Recurrence.MonthDays,
			Parity: func() *string {
				if task.Recurrence.Parity != nil {
					p := string(*task.Recurrence.Parity)
					return &p
				}
				return nil
			}(),
			StartDate: task.Recurrence.StartDate.Format(time.RFC3339),
		}

		if task.Recurrence.EndDate != nil {
			endStr := task.Recurrence.EndDate.Format(time.RFC3339)
			dto.Recurrence.EndDate = &endStr
		}

		if len(task.Recurrence.SpecificDates) > 0 {
			dates := make([]string, len(task.Recurrence.SpecificDates))
			for i, d := range task.Recurrence.SpecificDates {
				dates[i] = d.Format(time.RFC3339)
			}
			dto.Recurrence.SpecificDates = dates
		}
	}

	return dto
}
