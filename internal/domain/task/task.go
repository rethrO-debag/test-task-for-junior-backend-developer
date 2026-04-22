package task

import "time"

type Status string

const (
	StatusNew        Status = "new"
	StatusInProgress Status = "in_progress"
	StatusDone       Status = "done"
)

type RecurrenceType string

const (
	RecurrenceNone     RecurrenceType = "none"     // разовая задача
	RecurrenceDaily    RecurrenceType = "daily"    // каждые N дней
	RecurrenceMonthly  RecurrenceType = "monthly"  // определенные числа месяца
	RecurrenceSpecific RecurrenceType = "specific" // конкретные даты
	RecurrenceParity   RecurrenceType = "parity"   // четные/нечетные дни
)

type ParityType string

const (
	ParityEven ParityType = "even" // четные дни
	ParityOdd  ParityType = "odd"  // нечетные дни
)

type RecurrenceConfig struct {
	Type          RecurrenceType `json:"type"`
	Interval      *int           `json:"interval,omitempty"`       // для daily: каждые N дней
	MonthDays     []int          `json:"month_days,omitempty"`     // для monthly: числа месяца (1-30)
	SpecificDates []time.Time    `json:"specific_dates,omitempty"` // для specific: конкретные даты
	Parity        *ParityType    `json:"parity,omitempty"`         // для parity: even/odd
	StartDate     time.Time      `json:"start_date"`               // дата начала
	EndDate       *time.Time     `json:"end_date,omitempty"`       // дата окончания (опционально)
}
type Task struct {
	ID             int64             `json:"id"`
	Title          string            `json:"title"`
	Description    string            `json:"description"`
	Status         Status            `json:"status"`
	Recurrence     *RecurrenceConfig `json:"recurrence,omitempty"`
	ParentID       *int64            `json:"parent_id,omitempty"`       // <- должно быть с большой буквы
	OccurrenceDate *time.Time        `json:"occurrence_date,omitempty"` // <- должно быть с большой буквы
	CreatedAt      time.Time         `json:"created_at"`
	UpdatedAt      time.Time         `json:"updated_at"`
}

func (s Status) Valid() bool {
	switch s {
	case StatusNew, StatusInProgress, StatusDone:
		return true
	default:
		return false
	}
}

func (r *RecurrenceConfig) Validate() error {
	if r == nil {
		return nil
	}

	if r.StartDate.IsZero() {
		return ErrInvalidRecurrence
	}

	switch r.Type {
	case RecurrenceDaily:
		if r.Interval == nil || *r.Interval < 1 {
			return ErrInvalidRecurrence
		}
	case RecurrenceMonthly:
		if len(r.MonthDays) == 0 {
			return ErrInvalidRecurrence
		}
		for _, day := range r.MonthDays {
			if day < 1 || day > 30 {
				return ErrInvalidRecurrence
			}
		}
	case RecurrenceSpecific:
		if len(r.SpecificDates) == 0 {
			return ErrInvalidRecurrence
		}
	case RecurrenceParity:
		if r.Parity == nil || (*r.Parity != ParityEven && *r.Parity != ParityOdd) {
			return ErrInvalidRecurrence
		}
	case RecurrenceNone:
		// valid
	default:
		return ErrInvalidRecurrence
	}

	return nil
}
