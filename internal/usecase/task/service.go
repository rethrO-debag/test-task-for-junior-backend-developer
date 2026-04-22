package task

import (
	"context"
	"fmt"
	"strings"
	"time"

	taskdomain "example.com/taskservice/internal/domain/task"
)

type Service struct {
	repo      Repository
	generator *RecurrenceGenerator
	now       func() time.Time
}

func NewService(repo Repository) *Service {
	return &Service{
		repo:      repo,
		generator: NewRecurrenceGenerator(),
		now:       func() time.Time { return time.Now().UTC() },
	}
}

func (s *Service) Create(ctx context.Context, input CreateInput) (*taskdomain.Task, error) {
	normalized, err := s.validateCreateInput(input)
	if err != nil {
		return nil, err
	}

	// Валидируем recurrence конфигурацию
	if normalized.Recurrence != nil {
		if err := normalized.Recurrence.Validate(); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrInvalidInput, err)
		}
	}

	model := &taskdomain.Task{
		Title:       normalized.Title,
		Description: normalized.Description,
		Status:      normalized.Status,
		Recurrence:  normalized.Recurrence,
	}

	now := s.now()
	model.CreatedAt = now
	model.UpdatedAt = now

	// Если это периодическая задача, устанавливаем parent_id = nil (это шаблон)
	if model.Recurrence != nil && model.Recurrence.Type != taskdomain.RecurrenceNone {
		// Создаем шаблон
		created, err := s.repo.Create(ctx, model)
		if err != nil {
			return nil, err
		}

		// Генерируем первые экземпляры
		if err := s.GenerateOccurrences(ctx, created.ID); err != nil {
			// Логируем ошибку, но не прерываем создание
			// В реальном приложении лучше использовать логгер
			fmt.Printf("failed to generate occurrences: %v\n", err)
		}

		return created, nil
	}

	// Обычная задача
	return s.repo.Create(ctx, model)
}

func (s *Service) GetByID(ctx context.Context, id int64) (*taskdomain.Task, error) {
	if id <= 0 {
		return nil, fmt.Errorf("%w: id must be positive", ErrInvalidInput)
	}

	return s.repo.GetByID(ctx, id)
}

func (s *Service) Update(ctx context.Context, id int64, input UpdateInput) (*taskdomain.Task, error) {
	if id <= 0 {
		return nil, fmt.Errorf("%w: id must be positive", ErrInvalidInput)
	}

	normalized, err := s.validateUpdateInput(input)
	if err != nil {
		return nil, err
	}

	if normalized.Recurrence != nil {
		if err := normalized.Recurrence.Validate(); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrInvalidInput, err)
		}
	}

	model := &taskdomain.Task{
		ID:          id,
		Title:       normalized.Title,
		Description: normalized.Description,
		Status:      normalized.Status,
		Recurrence:  normalized.Recurrence,
		UpdatedAt:   s.now(),
	}

	updated, err := s.repo.Update(ctx, model)
	if err != nil {
		return nil, err
	}

	// Если изменилась периодичность, перегенерируем экземпляры
	if updated.Recurrence != nil {
		// Удаляем старые экземпляры
		existing, _ := s.repo.ListByParent(ctx, updated.ID)
		for _, occ := range existing {
			_ = s.repo.Delete(ctx, occ.ID)
		}

		// Генерируем новые
		_ = s.GenerateOccurrences(ctx, updated.ID)
	}

	return updated, nil
}

func (s *Service) Delete(ctx context.Context, id int64) error {
	if id <= 0 {
		return fmt.Errorf("%w: id must be positive", ErrInvalidInput)
	}

	// Если удаляем шаблон, удаляем и все его экземпляры
	task, err := s.repo.GetByID(ctx, id)
	if err == nil && task.Recurrence != nil && task.ParentID == nil {
		occurrences, _ := s.repo.ListByParent(ctx, id)
		for _, occ := range occurrences {
			_ = s.repo.Delete(ctx, occ.ID)
		}
	}

	return s.repo.Delete(ctx, id)
}

func (s *Service) List(ctx context.Context) ([]taskdomain.Task, error) {
	tasks, err := s.repo.List(ctx)
	if err != nil {
		return nil, err
	}

	// Фильтруем только экземпляры (не шаблоны) или показываем все?
	// По умолчанию показываем все, но можно добавить параметр фильтрации
	return tasks, nil
}

// GenerateOccurrences генерирует экземпляры периодической задачи
func (s *Service) GenerateOccurrences(ctx context.Context, parentID int64) error {
	parent, err := s.repo.GetByID(ctx, parentID)
	if err != nil {
		return err
	}

	if parent.Recurrence == nil || parent.Recurrence.Type == taskdomain.RecurrenceNone {
		return nil
	}

	// Генерируем следующие 10 дат (можно настроить)
	fromDate := s.now()
	dates, err := s.generator.GenerateNextDates(parent.Recurrence, fromDate, 10)
	if err != nil {
		return err
	}

	// Создаем экземпляры задач
	for _, date := range dates {
		// Проверяем, не существует ли уже экземпляр на эту дату
		existing, _ := s.repo.ListByParent(ctx, parentID)
		exists := false
		for _, occ := range existing {
			if occ.OccurrenceDate != nil && occ.OccurrenceDate.Equal(date) {
				exists = true
				break
			}
		}

		if !exists {
			occurrence := &taskdomain.Task{
				Title:          parent.Title,
				Description:    parent.Description,
				Status:         taskdomain.StatusNew,
				ParentID:       &parentID,
				OccurrenceDate: &date,
				CreatedAt:      s.now(),
				UpdatedAt:      s.now(),
			}

			if _, err := s.repo.Create(ctx, occurrence); err != nil {
				return err
			}
		}
	}

	return nil
}

func (s *Service) validateCreateInput(input CreateInput) (CreateInput, error) {
	input.Title = strings.TrimSpace(input.Title)
	input.Description = strings.TrimSpace(input.Description)

	if input.Title == "" {
		return CreateInput{}, fmt.Errorf("%w: title is required", ErrInvalidInput)
	}

	if input.Status == "" {
		input.Status = taskdomain.StatusNew
	}

	if !input.Status.Valid() {
		return CreateInput{}, fmt.Errorf("%w: invalid status", ErrInvalidInput)
	}

	return input, nil
}

func (s *Service) validateUpdateInput(input UpdateInput) (UpdateInput, error) {
	input.Title = strings.TrimSpace(input.Title)
	input.Description = strings.TrimSpace(input.Description)

	if input.Title == "" {
		return UpdateInput{}, fmt.Errorf("%w: title is required", ErrInvalidInput)
	}

	if !input.Status.Valid() {
		return UpdateInput{}, fmt.Errorf("%w: invalid status", ErrInvalidInput)
	}

	return input, nil
}
