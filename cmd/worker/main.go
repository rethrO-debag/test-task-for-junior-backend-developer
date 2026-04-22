package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	infrastructurepostgres "example.com/taskservice/internal/infrastructure/postgres"
	postgresrepo "example.com/taskservice/internal/repository/postgres"
	"example.com/taskservice/internal/usecase/task"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))

	dsn := os.Getenv("DATABASE_DSN")
	if dsn == "" {
		dsn = "postgres://postgres:postgres@localhost:5432/taskservice?sslmode=disable"
	}

	ctx := context.Background()
	pool, err := infrastructurepostgres.Open(ctx, dsn)
	if err != nil {
		logger.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	repo := postgresrepo.New(pool)
	service := task.NewService(repo)

	// Запускаем генерацию каждый час
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	logger.Info("worker started - generating recurring tasks")

	// Сразу запускаем генерацию при старте
	logger.Info("running initial generation")
	generateAllTasks(ctx, service, repo, logger)

	// Затем по расписанию
	for range ticker.C {
		logger.Info("running scheduled generation")
		generateAllTasks(ctx, service, repo, logger)
	}
}

func generateAllTasks(ctx context.Context, service *task.Service, repo *postgresrepo.Repository, logger *slog.Logger) {
	tasks, err := repo.List(ctx)
	if err != nil {
		logger.Error("failed to list tasks", "error", err)
		return
	}

	generated := 0
	for _, t := range tasks {
		// Генерируем только для шаблонов (ParentID == nil) у которых есть recurrence
		if t.Recurrence != nil && t.ParentID == nil {
			if err := service.GenerateOccurrences(ctx, t.ID); err != nil {
				logger.Error("failed to generate occurrences",
					"task_id", t.ID,
					"task_title", t.Title,
					"error", err)
			} else {
				generated++
			}
		}
	}

	if generated > 0 {
		logger.Info("generated task occurrences", "count", generated)
	}
}
