#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

BASE_URL="http://localhost:8080/api/v1/tasks"
SWAGGER_URL="http://localhost:8080/swagger/"

# Глобальные переменные для хранения ID созданных задач
declare -A TASK_IDS

# Функция проверки доступности сервиса
check_service() {
    echo -e "${CYAN}=== Проверка доступности сервиса ===${NC}"
    
    # Проверка API
    echo -n "Проверка API (localhost:8080)... "
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null)
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
        echo -e "${GREEN}✅ Доступно${NC}"
        API_AVAILABLE=true
    else
        echo -e "${RED}❌ Недоступно${NC}"
        API_AVAILABLE=false
    fi
    
    # Проверка Swagger
    echo -n "Проверка Swagger UI... "
    SWAGGER_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SWAGGER_URL" 2>/dev/null)
    
    if [ "$SWAGGER_CODE" = "200" ]; then
        echo -e "${GREEN}✅ Доступно${NC}"
    else
        echo -e "${RED}❌ Недоступно${NC}"
    fi
    
    # Проверка Docker контейнеров
    if command -v docker &> /dev/null; then
        echo -n "Проверка Docker контейнеров... "
        if docker ps --format 'table {{.Names}}' | grep -q "app\|worker\|postgres"; then
            echo -e "${GREEN}✅ Контейнеры запущены${NC}"
            docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E "app|worker|postgres"
        else
            echo -e "${YELLOW}⚠️ Контейнеры не найдены (возможно, запущены локально)${NC}"
        fi
    fi
    
    echo ""
    
    if [ "$API_AVAILABLE" = false ]; then
        echo -e "${RED}❌ Сервис недоступен!${NC}"
        echo -e "${YELLOW}Возможные решения:${NC}"
        echo "  1. Запустите сервис: docker compose up --build"
        echo "  2. Или локально: go run cmd/api/main.go"
        echo "  3. Проверьте, что порт 8080 не занят: lsof -i :8080"
        echo ""
        echo -n "Хотите продолжить без доступа к API? (y/n): "
        read continue_anyway
        if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
            exit 1
        fi
    fi
    
    return 0
}

# Функция ожидания запуска сервиса
wait_for_service() {
    echo -e "${CYAN}=== Ожидание запуска сервиса ===${NC}"
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo -n "Попытка $attempt/$max_attempts... "
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null)
        
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
            echo -e "${GREEN}✅ Сервис запущен${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}Ожидание...${NC}"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}❌ Сервис не запустился за $max_attempts попыток${NC}"
    return 1
}

# Функция для вывода информации о системе
show_system_info() {
    echo -e "${CYAN}=== Информация о системе ===${NC}"
    
    # Проверка Docker
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d ' ' -f3 | tr -d ',')
        echo -e "Docker: ${GREEN}$DOCKER_VERSION${NC}"
    else
        echo -e "Docker: ${RED}не установлен${NC}"
    fi
    
    # Проверка curl
    if command -v curl &> /dev/null; then
        CURL_VERSION=$(curl --version | head -1 | cut -d ' ' -f2)
        echo -e "curl: ${GREEN}$CURL_VERSION${NC}"
    fi
    
    # Проверка jq
    if command -v jq &> /dev/null; then
        JQ_VERSION=$(jq --version)
        echo -e "jq: ${GREEN}$JQ_VERSION${NC}"
    else
        echo -e "jq: ${YELLOW}не установлен (рекомендуется для форматирования JSON)${NC}"
        echo "  Установка: brew install jq (macOS) или apt-get install jq (Linux)"
    fi
    
    # Проверка порта
    echo -n "Порт 8080: "
    if lsof -i :8080 &> /dev/null || netstat -an 2>/dev/null | grep -q ":8080.*LISTEN"; then
        echo -e "${YELLOW}занят${NC}"
        echo "  Процессы на порту 8080:"
        lsof -i :8080 2>/dev/null || netstat -an 2>/dev/null | grep ":8080"
    else
        echo -e "${GREEN}свободен${NC}"
    fi
    
    echo ""
}

# Функция для вывода меню
show_menu() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}   Тестирование Task Service${NC}"
    echo -e "${BLUE}=====================================${NC}"
    
    # Показываем статус сервиса
    if [ "$API_AVAILABLE" = true ]; then
        echo -e "${GREEN}🟢 Сервис ДОСТУПЕН${NC}"
    else
        echo -e "${RED}🔴 Сервис НЕДОСТУПЕН${NC}"
    fi
    echo -e "${BLUE}=====================================${NC}"
    
    echo -e "${GREEN}1.${NC} Создание задачи (автоматически)"
    echo -e "${GREEN}2.${NC} Создание задачи (ручной ввод)"
    echo -e "${GREEN}3.${NC} Получение всех задач"
    echo -e "${GREEN}4.${NC} Получение задачи по ID"
    echo -e "${GREEN}5.${NC} Обновление задачи (автоматически)"
    echo -e "${GREEN}6.${NC} Обновление задачи (ручной ввод)"
    echo -e "${GREEN}7.${NC} Удаление задачи"
    echo -e "${GREEN}8.${NC} Проверка worker (логи)"
    echo -e "${GREEN}9.${NC} Проверка экземпляров периодических задач"
    echo -e "${GREEN}10.${NC} Проверка обработки ошибок"
    echo -e "${GREEN}11.${NC} Полный автотест"
    echo -e "${GREEN}12.${NC} Очистить все задачи"
    echo -e "${GREEN}13.${NC} Информация о системе"
    echo -e "${GREEN}14.${NC} Проверить доступность сервиса"
    echo -e "${RED}0.${NC} Выход"
    echo -e "${BLUE}=====================================${NC}"
    
    if [ -n "${TASK_IDS["last"]}" ]; then
        echo -e "${CYAN}📌 Последний созданный ID: ${TASK_IDS["last"]}${NC}"
    fi
    
    echo -n "Выберите пункт (0-14): "
}

# Функция для создания задачи (автоматически)
create_task_auto() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен. Невозможно создать задачу.${NC}\n"
        return
    fi
    
    echo -e "${GREEN}=== Создание задачи (автоматически) ===${NC}"
    echo "Выберите тип задачи:"
    echo "1. Обычная задача"
    echo "2. Ежедневная задача"
    echo "3. Ежемесячная задача"
    echo "4. Задача на конкретные даты"
    echo "5. Задача на четные дни"
    echo -n "Выберите (1-5): "
    read type_choice
    
    case $type_choice in
        1)
            RESPONSE=$(curl -s -X POST $BASE_URL \
              -H "Content-Type: application/json" \
              -d '{
                "title": "Обычная задача",
                "description": "Тестовая задача без периодичности",
                "status": "new"
              }')
            ;;
        2)
            RESPONSE=$(curl -s -X POST $BASE_URL \
              -H "Content-Type: application/json" \
              -d '{
                "title": "Ежедневная проверка",
                "description": "Проверять логи каждые 2 дня",
                "status": "new",
                "recurrence": {
                  "type": "daily",
                  "interval": 2,
                  "start_date": "2026-04-22T00:00:00Z",
                  "end_date": "2026-05-22T00:00:00Z"
                }
              }')
            ;;
        3)
            RESPONSE=$(curl -s -X POST $BASE_URL \
              -H "Content-Type: application/json" \
              -d '{
                "title": "Формирование отчета",
                "description": "Подготовить финансовый отчет",
                "status": "new",
                "recurrence": {
                  "type": "monthly",
                  "month_days": [1, 15],
                  "start_date": "2026-04-01T00:00:00Z"
                }
              }')
            ;;
        4)
            RESPONSE=$(curl -s -X POST $BASE_URL \
              -H "Content-Type: application/json" \
              -d '{
                "title": "Инвентаризация",
                "description": "Провести инвентаризацию склада",
                "status": "new",
                "recurrence": {
                  "type": "specific",
                  "specific_dates": ["2026-05-10T00:00:00Z", "2026-05-20T00:00:00Z"],
                  "start_date": "2026-05-10T00:00:00Z"
                }
              }')
            ;;
        5)
            RESPONSE=$(curl -s -X POST $BASE_URL \
              -H "Content-Type: application/json" \
              -d '{
                "title": "Обзвон клиентов",
                "description": "Обзванивать клиентов в четные дни",
                "status": "new",
                "recurrence": {
                  "type": "parity",
                  "parity": "even",
                  "start_date": "2026-04-01T00:00:00Z"
                }
              }')
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            return
            ;;
    esac
    
    echo "$RESPONSE" | jq '.'
    TASK_ID=$(echo "$RESPONSE" | jq -r '.id')
    if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ]; then
        TASK_IDS["last"]=$TASK_ID
        echo -e "${GREEN}✅ Создана задача с ID: $TASK_ID${NC}\n"
    else
        echo -e "${RED}❌ Ошибка при создании задачи${NC}\n"
    fi
}

# Функция для создания задачи (ручной ввод)
create_task_manual() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен. Невозможно создать задачу.${NC}\n"
        return
    fi
    
    echo -e "${GREEN}=== Создание задачи (ручной ввод) ===${NC}"
    
    echo -n "Введите заголовок задачи: "
    read title
    
    echo -n "Введите описание (Enter - пропустить): "
    read description
    
    echo -n "Введите статус (new/in_progress/done) [new]: "
    read status
    status=${status:-new}
    
    echo -n "Добавить периодичность? (y/n): "
    read has_recurrence
    
    BODY="{\"title\":\"$title\",\"description\":\"$description\",\"status\":\"$status\""
    
    if [ "$has_recurrence" = "y" ] || [ "$has_recurrence" = "Y" ]; then
        echo -e "${YELLOW}Выберите тип периодичности:${NC}"
        echo "1. daily (каждые N дней)"
        echo "2. monthly (определенные числа месяца)"
        echo "3. specific (конкретные даты)"
        echo "4. parity (четные/нечетные дни)"
        echo -n "Выберите (1-4): "
        read rec_type
        
        case $rec_type in
            1)
                echo -n "Интервал в днях: "
                read interval
                echo -n "Дата начала (YYYY-MM-DD): "
                read start_date
                BODY="$BODY,\"recurrence\":{\"type\":\"daily\",\"interval\":$interval,\"start_date\":\"${start_date}T00:00:00Z\"}"
                ;;
            2)
                echo -n "Числа месяца через запятую (например: 1,15): "
                read month_days
                echo -n "Дата начала (YYYY-MM-DD): "
                read start_date
                BODY="$BODY,\"recurrence\":{\"type\":\"monthly\",\"month_days\":[$month_days],\"start_date\":\"${start_date}T00:00:00Z\"}"
                ;;
            3)
                echo -n "Даты через запятую (YYYY-MM-DD, YYYY-MM-DD): "
                read dates
                IFS=',' read -ra date_array <<< "$dates"
                formatted_dates=""
                first_date=""
                for date in "${date_array[@]}"; do
                    trimmed=$(echo "$date" | xargs)
                    if [ -z "$first_date" ]; then
                        first_date="$trimmed"
                    fi
                    if [ -n "$formatted_dates" ]; then
                        formatted_dates="$formatted_dates,"
                    fi
                    formatted_dates="$formatted_dates\"${trimmed}T00:00:00Z\""
                done
                BODY="$BODY,\"recurrence\":{\"type\":\"specific\",\"specific_dates\":[$formatted_dates],\"start_date\":\"${first_date}T00:00:00Z\"}"
                ;;
            4)
                echo -n "Тип четности (even/odd): "
                read parity
                echo -n "Дата начала (YYYY-MM-DD): "
                read start_date
                BODY="$BODY,\"recurrence\":{\"type\":\"parity\",\"parity\":\"$parity\",\"start_date\":\"${start_date}T00:00:00Z\"}"
                ;;
        esac
    fi
    
    BODY="$BODY}"
    
    echo -e "${YELLOW}Отправляем запрос:${NC}"
    echo "$BODY" | jq '.'
    
    RESPONSE=$(curl -s -X POST $BASE_URL \
      -H "Content-Type: application/json" \
      -d "$BODY")
    
    echo "$RESPONSE" | jq '.'
    TASK_ID=$(echo "$RESPONSE" | jq -r '.id')
    if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ]; then
        TASK_IDS["last"]=$TASK_ID
        echo -e "${GREEN}✅ Создана задача с ID: $TASK_ID${NC}\n"
    else
        echo -e "${RED}❌ Ошибка при создании задачи${NC}\n"
    fi
}

# Функция для получения всех задач
get_all_tasks() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен.${NC}\n"
        return
    fi
    
    echo -e "${GREEN}=== Получение всех задач ===${NC}"
    RESPONSE=$(curl -s $BASE_URL)
    COUNT=$(echo "$RESPONSE" | jq 'length' 2>/dev/null || echo "0")
    echo -e "${YELLOW}Всего задач: $COUNT${NC}\n"
    echo "$RESPONSE" | jq '.[] | {id, title, status, parent_id, occurrence_date}' 2>/dev/null || echo "Нет задач или ошибка формата"
    echo -e "\n"
}

# Функция для получения задачи по ID
get_task_by_id() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен.${NC}\n"
        return
    fi
    
    echo -e "${GREEN}=== Получение задачи по ID ===${NC}"
    echo -n "Введите ID задачи (Enter - использовать последний созданный): "
    read id
    if [ -z "$id" ] && [ -n "${TASK_IDS["last"]}" ]; then
        id=${TASK_IDS["last"]}
        echo -e "${YELLOW}Использую последний ID: $id${NC}"
    fi
    if [ -n "$id" ]; then
        RESPONSE=$(curl -s "$BASE_URL/$id")
        STATUS=$(echo "$RESPONSE" | jq -r '.error // "200"')
        if [ "$STATUS" = "200" ] || [ "$(echo "$RESPONSE" | jq -r '.id')" != "null" ]; then
            echo "$RESPONSE" | jq '.'
        else
            echo -e "${RED}❌ Задача с ID $id не найдена${NC}"
            echo "$RESPONSE" | jq '.'
        fi
        echo -e "\n"
    else
        echo -e "${RED}❌ ID не указан${NC}\n"
    fi
}

# Функция для обновления задачи (автоматически)
update_task_auto() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен.${NC}\n"
        return
    fi
    
    echo -e "${GREEN}=== Обновление задачи (автоматически) ===${NC}"
    echo -n "Введите ID задачи для обновления (Enter - использовать последний): "
    read id
    if [ -z "$id" ] && [ -n "${TASK_IDS["last"]}" ]; then
        id=${TASK_IDS["last"]}
        echo -e "${YELLOW}Использую последний ID: $id${NC}"
    fi
    if [ -n "$id" ]; then
        echo -e "${YELLOW}Обновляем задачу $id до статуса 'in_progress'${NC}"
        RESPONSE=$(curl -s -X PUT "$BASE_URL/$id" \
          -H "Content-Type: application/json" \
          -d '{
            "title": "Обновленная задача",
            "description": "Описание обновлено автоматически",
            "status": "in_progress"
          }')
        echo "$RESPONSE" | jq '.'
        echo -e "${GREEN}✅ Задача обновлена${NC}\n"
    else
        echo -e "${RED}❌ ID не указан${NC}\n"
    fi
}

# Функция для обновления задачи (ручной ввод)
update_task_manual() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен.${NC}\n"
        return
    fi
    
    echo -e "${GREEN}=== Обновление задачи (ручной ввод) ===${NC}"
    echo -n "Введите ID задачи для обновления: "
    read id
    if [ -z "$id" ]; then
        echo -e "${RED}❌ ID не указан${NC}\n"
        return
    fi
    
    echo -n "Новый заголовок (Enter - оставить без изменений): "
    read title
    
    echo -n "Новое описание (Enter - оставить без изменений): "
    read description
    
    echo -n "Новый статус (new/in_progress/done): "
    read status
    
    # Сначала получаем текущую задачу
    CURRENT=$(curl -s "$BASE_URL/$id")
    CURRENT_TITLE=$(echo "$CURRENT" | jq -r '.title')
    CURRENT_DESC=$(echo "$CURRENT" | jq -r '.description')
    CURRENT_STATUS=$(echo "$CURRENT" | jq -r '.status')
    
    # Используем новые значения или старые
    title=${title:-$CURRENT_TITLE}
    description=${description:-$CURRENT_DESC}
    status=${status:-$CURRENT_STATUS}
    
    BODY="{\"title\":\"$title\",\"description\":\"$description\",\"status\":\"$status\"}"
    
    echo -e "${YELLOW}Отправляем запрос:${NC}"
    echo "$BODY" | jq '.'
    
    RESPONSE=$(curl -s -X PUT "$BASE_URL/$id" \
      -H "Content-Type: application/json" \
      -d "$BODY")
    
    echo "$RESPONSE" | jq '.'
    echo -e "${GREEN}✅ Задача обновлена${NC}\n"
}

# Функция для удаления задачи
delete_task() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен.${NC}\n"
        return
    fi
    
    echo -e "${RED}=== Удаление задачи ===${NC}"
    echo -n "Введите ID задачи для удаления (Enter - использовать последний): "
    read id
    if [ -z "$id" ] && [ -n "${TASK_IDS["last"]}" ]; then
        id=${TASK_IDS["last"]}
        echo -e "${YELLOW}Использую последний ID: $id${NC}"
    fi
    if [ -n "$id" ]; then
        echo -e "${YELLOW}Удаляем задачу $id...${NC}"
        RESPONSE=$(curl -s -X DELETE "$BASE_URL/$id")
        if [ -z "$RESPONSE" ]; then
            echo -e "${GREEN}✅ Задача $id удалена${NC}"
            unset TASK_IDS["last"]
        else
            echo "$RESPONSE" | jq '.'
        fi
        echo -e "\n"
    else
        echo -e "${RED}❌ ID не указан${NC}\n"
    fi
}

# Функция для проверки worker
check_worker() {
    echo -e "${YELLOW}=== Проверка worker ===${NC}"
    echo -e "Последние 20 строк логов worker:\n"
    docker compose logs worker --tail 20 2>/dev/null || echo "Worker не запущен или Docker не используется"
    echo -e "\n"
}

# Функция для проверки экземпляров
check_occurrences() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен.${NC}\n"
        return
    fi
    
    echo -e "${GREEN}=== Экземпляры периодических задач ===${NC}"
    RESPONSE=$(curl -s $BASE_URL)
    COUNT=$(echo "$RESPONSE" | jq '[.[] | select(.parent_id != null)] | length' 2>/dev/null || echo "0")
    echo -e "${YELLOW}Найдено экземпляров: $COUNT${NC}\n"
    echo "$RESPONSE" | jq '.[] | select(.parent_id != null) | {id, title, parent_id, occurrence_date, status}' 2>/dev/null
    echo -e "\n"
}

# Функция для проверки ошибок
check_errors() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен.${NC}\n"
        return
    fi
    
    echo -e "${RED}=== Проверка обработки ошибок ===${NC}\n"
    
    echo -e "${YELLOW}1. Создание задачи без title (ожидается 400):${NC}"
    curl -s -X POST $BASE_URL \
      -H "Content-Type: application/json" \
      -d '{"description": "Нет заголовка", "status": "new"}' | jq '.'
    
    echo -e "\n${YELLOW}2. Получение несуществующей задачи (ожидается 404):${NC}"
    curl -s "$BASE_URL/99999" | jq '.'
    
    echo -e "\n${YELLOW}3. Создание задачи с неверной периодичностью (ожидается 400):${NC}"
    curl -s -X POST $BASE_URL \
      -H "Content-Type: application/json" \
      -d '{
        "title": "Неверная периодичность",
        "recurrence": {
          "type": "daily",
          "interval": 0,
          "start_date": "2026-04-22T00:00:00Z"
        }
      }' | jq '.'
    
    echo -e "\n${YELLOW}4. Обновление несуществующей задачи (ожидается 404):${NC}"
    curl -s -X PUT "$BASE_URL/99999" \
      -H "Content-Type: application/json" \
      -d '{"title": "Не существует", "status": "done"}' | jq '.'
    
    echo -e "\n${YELLOW}5. Удаление несуществующей задачи (ожидается 404):${NC}"
    curl -s -X DELETE "$BASE_URL/99999" | jq '.'
    
    echo -e "\n"
}

# Функция для полного автотеста
full_autotest() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен. Невозможно запустить автотест.${NC}\n"
        echo -n "Запустить сервис сейчас? (y/n): "
        read run_service
        if [ "$run_service" = "y" ] || [ "$run_service" = "Y" ]; then
            echo -e "${YELLOW}Запуск сервиса...${NC}"
            docker compose up -d 2>/dev/null || go run cmd/api/main.go &
            sleep 5
            check_service
            if [ "$API_AVAILABLE" != true ]; then
                echo -e "${RED}❌ Не удалось запустить сервис${NC}"
                return
            fi
        else
            return
        fi
    fi
    
    echo -e "${BLUE}=== Запуск полного автотеста ===${NC}\n"
    
    # Создаем задачи
    create_task_auto
    sleep 1
    
    create_task_auto
    sleep 1
    
    # Получаем все задачи
    get_all_tasks
    
    # Обновляем последнюю задачу
    if [ -n "${TASK_IDS["last"]}" ]; then
        update_task_auto
    fi
    
    # Проверяем worker
    check_worker
    
    # Проверяем экземпляры
    check_occurrences
    
    # Проверяем ошибки
    check_errors
    
    echo -e "${GREEN}✅ Полный автотест завершен${NC}\n"
}

# Функция для очистки всех задач
clean_all() {
    if [ "$API_AVAILABLE" != true ]; then
        echo -e "${RED}❌ Сервис недоступен.${NC}\n"
        return
    fi
    
    echo -e "${RED}=== Очистка всех задач ===${NC}"
    echo -n "Вы уверены? (y/n): "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # Получаем все ID и удаляем
        curl -s $BASE_URL | jq -r '.[].id' 2>/dev/null | while read id; do
            echo -e "Удаление задачи ID: $id"
            curl -s -X DELETE "$BASE_URL/$id"
            echo ""
        done
        TASK_IDS=()
        echo -e "${GREEN}✅ Все задачи удалены${NC}\n"
    else
        echo -e "${YELLOW}Отмена${NC}\n"
    fi
}

# Функция для проверки доступности
check_availability() {
    check_service
    if [ "$API_AVAILABLE" = false ]; then
        echo -n "Хотите дождаться запуска сервиса? (y/n): "
        read wait_service
        if [ "$wait_service" = "y" ] || [ "$wait_service" = "Y" ]; then
            wait_for_service
            check_service
        fi
    fi
}

# Основная проверка при запуске
clear
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}   Task Service Test Suite${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Проверяем доступность сервиса
check_service

# Если сервис недоступен, предлагаем дождаться
if [ "$API_AVAILABLE" = false ]; then
    echo -n "Хотите дождаться запуска сервиса? (y/n): "
    read wait_service
    if [ "$wait_service" = "y" ] || [ "$wait_service" = "Y" ]; then
        wait_for_service
        check_service
    fi
fi

# Главный цикл
while true; do
    show_menu
    read choice
    case $choice in
        1) create_task_auto ;;
        2) create_task_manual ;;
        3) get_all_tasks ;;
        4) get_task_by_id ;;
        5) update_task_auto ;;
        6) update_task_manual ;;
        7) delete_task ;;
        8) check_worker ;;
        9) check_occurrences ;;
        10) check_errors ;;
        11) full_autotest ;;
        12) clean_all ;;
        13) show_system_info ;;
        14) check_availability ;;
        0) echo -e "${GREEN}До свидания!${NC}"; exit 0 ;;
        *) echo -e "${RED}Неверный выбор. Пожалуйста, выберите пункт от 0 до 14${NC}\n" ;;
    esac
    
    echo -e "${YELLOW}Нажмите Enter для продолжения...${NC}"
    read
    clear
done