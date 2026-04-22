FROM golang:1.23.0-alpine AS builder

WORKDIR /src

RUN apk add --no-cache ca-certificates

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Собираем оба приложения
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/taskservice ./cmd/api
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/worker ./cmd/worker

FROM alpine:3.21

WORKDIR /app

RUN apk add --no-cache ca-certificates

# Копируем оба бинарника
COPY --from=builder /out/taskservice /app/taskservice
COPY --from=builder /out/worker /app/worker

EXPOSE 8080

CMD ["/app/taskservice"]