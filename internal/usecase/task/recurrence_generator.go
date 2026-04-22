package task

import (
	"time"

	taskdomain "example.com/taskservice/internal/domain/task"
)

type RecurrenceGenerator struct{}

func NewRecurrenceGenerator() *RecurrenceGenerator {
	return &RecurrenceGenerator{}
}

// GenerateNextDates генерирует следующие даты выполнения на основе конфигурации
func (g *RecurrenceGenerator) GenerateNextDates(config *taskdomain.RecurrenceConfig, fromDate time.Time, limit int) ([]time.Time, error) {
	if config == nil {
		return nil, nil
	}

	dates := make([]time.Time, 0)
	current := fromDate

	for len(dates) < limit {
		next := g.GetNextDate(config, current)
		if next.IsZero() {
			break
		}

		// Проверяем, не превысили ли дату окончания
		if config.EndDate != nil && next.After(*config.EndDate) {
			break
		}

		dates = append(dates, next)
		current = next.AddDate(0, 0, 1) // переходим к следующему дню
	}

	return dates, nil
}

// GetNextDate возвращает следующую дату выполнения после указанной даты
func (g *RecurrenceGenerator) GetNextDate(config *taskdomain.RecurrenceConfig, after time.Time) time.Time {
	if config == nil {
		return time.Time{}
	}

	// Нормализуем дату к началу дня
	after = time.Date(after.Year(), after.Month(), after.Day(), 0, 0, 0, 0, after.Location())

	switch config.Type {
	case taskdomain.RecurrenceDaily:
		return g.getNextDailyDate(config, after)
	case taskdomain.RecurrenceMonthly:
		return g.getNextMonthlyDate(config, after)
	case taskdomain.RecurrenceSpecific:
		return g.getNextSpecificDate(config, after)
	case taskdomain.RecurrenceParity:
		return g.getNextParityDate(config, after)
	default:
		return time.Time{}
	}
}

func (g *RecurrenceGenerator) getNextDailyDate(config *taskdomain.RecurrenceConfig, after time.Time) time.Time {
	interval := *config.Interval
	startDate := time.Date(config.StartDate.Year(), config.StartDate.Month(), config.StartDate.Day(), 0, 0, 0, 0, after.Location())

	// Если after раньше startDate, начинаем с startDate
	if after.Before(startDate) {
		return startDate
	}

	// Вычисляем разницу в днях
	daysDiff := int(after.Sub(startDate).Hours() / 24)

	// Находим следующую дату, которая соответствует интервалу
	nextDiff := ((daysDiff / interval) + 1) * interval
	nextDate := startDate.AddDate(0, 0, nextDiff)

	return nextDate
}

func (g *RecurrenceGenerator) getNextMonthlyDate(config *taskdomain.RecurrenceConfig, after time.Time) time.Time {
	startDate := time.Date(config.StartDate.Year(), config.StartDate.Month(), config.StartDate.Day(), 0, 0, 0, 0, after.Location())

	// Проверяем даты в текущем и следующих месяцах
	for i := 0; i < 12; i++ {
		checkDate := after.AddDate(0, i, 0)

		for _, day := range config.MonthDays {
			// Пропускаем 31 число (не во всех месяцах)
			if day > 28 && day > g.daysInMonth(checkDate.Year(), checkDate.Month()) {
				continue
			}

			candidate := time.Date(checkDate.Year(), checkDate.Month(), day, 0, 0, 0, 0, after.Location())

			// Дата должна быть после after и не раньше startDate
			if candidate.After(after) && (candidate.Equal(startDate) || candidate.After(startDate)) {
				return candidate
			}
		}
	}

	return time.Time{}
}

func (g *RecurrenceGenerator) getNextSpecificDate(config *taskdomain.RecurrenceConfig, after time.Time) time.Time {
	startDate := time.Date(config.StartDate.Year(), config.StartDate.Month(), config.StartDate.Day(), 0, 0, 0, 0, after.Location())

	for _, date := range config.SpecificDates {
		normalized := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, after.Location())

		if normalized.After(after) && (normalized.Equal(startDate) || normalized.After(startDate)) {
			return normalized
		}
	}

	return time.Time{}
}

func (g *RecurrenceGenerator) getNextParityDate(config *taskdomain.RecurrenceConfig, after time.Time) time.Time {
	startDate := time.Date(config.StartDate.Year(), config.StartDate.Month(), config.StartDate.Day(), 0, 0, 0, 0, after.Location())

	// Начинаем поиск с after+1 день
	current := after.AddDate(0, 0, 1)

	// Ищем в пределах следующих 31 дня
	for i := 0; i < 31; i++ {
		candidate := current.AddDate(0, 0, i)

		// Проверяем четность дня месяца
		day := candidate.Day()
		isEven := day%2 == 0

		matches := false
		if *config.Parity == taskdomain.ParityEven && isEven {
			matches = true
		} else if *config.Parity == taskdomain.ParityOdd && !isEven {
			matches = true
		}

		if matches && (candidate.Equal(startDate) || candidate.After(startDate)) {
			return candidate
		}
	}

	return time.Time{}
}

func (g *RecurrenceGenerator) daysInMonth(year int, month time.Month) int {
	return time.Date(year, month+1, 0, 0, 0, 0, 0, time.UTC).Day()
}
