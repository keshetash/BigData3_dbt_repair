# Лабораторная работа №3
**Тема:** Автоматизированная работа с хранилищами данных с использованием фреймворка dbt  
**Вариант:** Сервис по ремонту техники

---

## Цель и задачи

Цель — научиться автоматизировать работу с хранилищами данных через dbt.

Задачи:
- установить dbt и настроить проект;
- написать staging-модель и витрины данных;
- запустить модели и поставить на расписание.

---

## Предметная область

Предметная область — сервис по ремонту бытовой и компьютерной техники. В системе фиксируются заказы клиентов, данные об устройствах, типах неисправностей, инженерах и используемых запчастях.

Основные сущности:

| Сущность | Описание |
|---|---|
| Клиент | ФИО, контактный телефон |
| Вид устройства | Смартфон, Ноутбук, Планшет, Компьютер, Телевизор |
| Тип неисправности | Аппаратная, Программная, Механическое повреждение |
| Инженер | ФИО специалиста |
| Заказ на ремонт | Стоимость, статус выполнения, дата |
| Запчасти | Наименование и стоимость использованных деталей |

---

## Используемые технологии

- Python 3.12.10
- dbt-core 1.11.10
- dbt-duckdb 1.10.1
- DuckDB 1.5.2 (встроенная аналитическая БД, не требует отдельного сервера)

---

## Шаг 1. Установка

dbt устанавливается через pip с адаптером для DuckDB:

```
py -3.12 -m pip install dbt-duckdb
```

Проверка установки:

```
dbt --version
```

```
Core:
  - installed: 1.11.10
  - latest:    1.11.10 - Up to date!

Plugins:
  - duckdb: 1.10.1 - Up to date!
```

При работе использовался Python 3.12, поскольку на момент выполнения работы dbt не поддерживает Python 3.14 из-за конфликта зависимостей с библиотекой mashumaro.

---

## Шаг 2. Конфигурация проекта

Проект инициализируется командой `dbt init repair_dbt`. После этого настраиваются два конфигурационных файла.

**profiles.yml** — подключение к базе данных:

```yaml
repair_dbt:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: repair_service.duckdb
```

Файл `repair_service.duckdb` создаётся автоматически в папке проекта при первом запуске — устанавливать отдельную СУБД не нужно.

**dbt_project.yml** — параметры проекта:

```yaml
name: repair_dbt
version: '1.0.0'
profile: repair_dbt
model-paths: ["models"]
models:
  repair_dbt:
    +materialized: view
```

Проверка подключения:

```
dbt debug --profiles-dir .
```

```
18:51:14  dbt version: 1.11.10
18:51:14  python version: 3.12.10
18:51:14  adapter type: duckdb
18:51:14  adapter version: 1.10.1
18:51:14    profiles.yml file [OK found and valid]
18:51:14    dbt_project.yml file [OK found and valid]
18:51:14   - git [OK found]
18:51:14  Connection:
18:51:14    database: repair_service
18:51:14    schema: main
18:51:14    path: repair_service.duckdb
18:51:20    Connection test: [OK connection ok]
18:51:20  All checks passed!
```

---

## Шаг 3. Структура моделей

В dbt модели делятся на слои. В данной работе реализованы два слоя:

```
models/
├── stg_repair_orders.sql      — staging-слой (сырые данные + валидация)
├── engineer_performance.sql   — витрина: статистика по инженерам
└── device_fault_analysis.sql  — витрина: анализ по типам устройств
```

Зависимость между моделями задаётся через макрос `{{ ref() }}` — dbt сам определяет порядок выполнения:

```
stg_repair_orders  →  engineer_performance
                   →  device_fault_analysis
```

---

## Шаг 4. Описание моделей

### stg_repair_orders.sql — Staging-модель

Staging-слой загружает исходные данные и проверяет их корректность. Данные содержат информацию обо всех шести сущностях в денормализованном виде.

Правила валидации:
- `repair_cost <= 0` — нулевая или отрицательная стоимость ремонта
- `part_cost < 0` — некорректная стоимость запчасти
- `client_name IS NULL` — отсутствует имя клиента
- `engineer_name IS NULL` — не назначен инженер

Каждой записи присваивается поле `validation_status`: **VALID** или **NOT VALID**. В витрины попадают только валидные записи.

```sql
WITH raw_data AS (
    SELECT * FROM (VALUES
        (1,  'Иванов Иван Иванович',      '+7-900-111-22-33', 'Смартфон',  'Samsung Galaxy S21',
         'Аппаратная неисправность', 'Разбит экран', 'Алексеев А.А.', 'Экран Samsung', 2500, 6500, 'Выдан', '2024-01-05'),
        ...
        (14, 'Баранова Светлана Юрьевна', '+7-900-500-55-66', 'Компьютер', 'Custom Build',
         'Аппаратная неисправность', 'Не работает USB', 'Васильев В.В.', 'Материнская плата', -500, 8000, 'Выдан', '2024-01-29')
        -- запись 14: part_cost = -500, получит статус NOT VALID
    ) AS t(order_id, client_name, client_phone, device_type, device_model,
           fault_type, fault_description, engineer_name, part_name,
           part_cost, repair_cost, status, order_date)
),
validated AS (
    SELECT *,
        CASE
            WHEN repair_cost <= 0  THEN 'NOT VALID'
            WHEN part_cost   <  0  THEN 'NOT VALID'
            WHEN client_name   IS NULL THEN 'NOT VALID'
            WHEN engineer_name IS NULL THEN 'NOT VALID'
            ELSE 'VALID'
        END AS validation_status
    FROM raw_data
)
SELECT * FROM validated
```

### engineer_performance.sql — Витрина 1

Агрегирует данные в разрезе инженеров: количество заказов по статусам, суммарная и средняя выручка, стоимость запчастей.

```sql
SELECT
    engineer_name,
    COUNT(*)                                                 AS total_orders,
    COUNT(CASE WHEN status = 'Выдан' THEN 1 END)            AS completed_orders,
    COUNT(CASE WHEN status = 'В работе' THEN 1 END)         AS in_progress_orders,
    COUNT(CASE WHEN status = 'Ожидает запчасти' THEN 1 END) AS waiting_parts_orders,
    ROUND(SUM(repair_cost), 2)                               AS total_revenue,
    ROUND(AVG(repair_cost), 2)                               AS avg_repair_cost,
    ROUND(SUM(part_cost), 2)                                 AS total_parts_cost
FROM {{ ref('stg_repair_orders') }}
WHERE validation_status = 'VALID'
GROUP BY engineer_name
ORDER BY total_revenue DESC
```

### device_fault_analysis.sql — Витрина 2

Показывает, какие неисправности встречаются чаще всего на каждом типе устройств и во сколько обходится их устранение.

```sql
SELECT
    device_type,
    fault_type,
    COUNT(*)                   AS orders_count,
    ROUND(AVG(repair_cost), 2) AS avg_repair_cost,
    ROUND(SUM(repair_cost), 2) AS total_revenue,
    ROUND(AVG(part_cost), 2)   AS avg_part_cost
FROM {{ ref('stg_repair_orders') }}
WHERE validation_status = 'VALID'
GROUP BY device_type, fault_type
ORDER BY device_type, orders_count DESC
```

---

## Шаг 5. Запуск

```
dbt run --profiles-dir .
```

```
18:51:20  Running with dbt=1.11.10
18:51:20  Registered adapter: duckdb=1.10.1
18:51:21  Found 3 models, 477 macros

18:51:21  Concurrency: 1 threads (target='dev')

18:51:21  1 of 3 START sql view model main.stg_repair_orders ............................. [RUN]
18:51:21  1 of 3 OK created sql view model main.stg_repair_orders ........................ [OK in 0.07s]
18:51:21  2 of 3 START sql view model main.device_fault_analysis ......................... [RUN]
18:51:21  2 of 3 OK created sql view model main.device_fault_analysis .................... [OK in 0.03s]
18:51:21  3 of 3 START sql view model main.engineer_performance .......................... [RUN]
18:51:21  3 of 3 OK created sql view model main.engineer_performance ..................... [OK in 0.03s]

18:51:21  Finished running 3 view models in 0 hours 0 minutes and 0.29 seconds (0.29s).
18:51:21  Completed successfully
18:51:21  Done. PASS=3 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=3
```

Все три модели успешно созданы.

---

## Шаг 6. Результаты

### Валидация заказов (stg_repair_orders)

```
 order_id                 client_name device_type  repair_cost validation_status
        1        Иванов Иван Иванович    Смартфон         6500             VALID
        2      Петрова Анна Сергеевна     Ноутбук         4800             VALID
        3     Сидоров Пётр Алексеевич     Планшет         2200             VALID
        4    Козлова Мария Дмитриевна    Смартфон         3500             VALID
        5   Новиков Дмитрий Фёдорович   Компьютер         5000             VALID
        6 Морозова Елена Владимировна     Ноутбук         2800             VALID
        7    Волков Андрей Николаевич   Телевизор        25000             VALID
        8     Соколова Ирина Павловна    Смартфон         1500             VALID
        9     Лебедев Сергей Игоревич   Компьютер         1800             VALID
       10  Попова Наталья Геннадьевна     Планшет         5500             VALID
       11    Зайцев Алексей Борисович     Ноутбук         2000             VALID
       12    Фёдорова Юлия Евгеньевна    Смартфон         4200             VALID
       13   Михайлов Кирилл Тимурович   Телевизор         3800             VALID
       14   Баранова Светлана Юрьевна   Компьютер         8000         NOT VALID
       15    Громов Евгений Романович    Смартфон         1200             VALID
```

Запись №14 получила статус NOT VALID — отрицательная стоимость запчасти (`part_cost = -500`). В витрины эта запись не включается.

### Витрина 1: эффективность инженеров

```
 engineer_name  total_orders  completed_orders  in_progress_orders  waiting_parts_orders  total_revenue  avg_repair_cost  total_parts_cost
 Дмитриев Д.Д.             2                 0                   2                     0        28800.0          14400.0           19200.0
 Алексеев А.А.             5                 3                   1                     1        16900.0           3380.0            4650.0
  Борисов Б.Б.             3                 3                   0                     0         9600.0           3200.0            4150.0
Григорьев Г.Г.             2                 0                   1                     0         7700.0           3850.0            3900.0
 Васильев В.В.             2                 0                   0                     1         6800.0           3400.0            2500.0
```

Наибольшую выручку обеспечивает Дмитриев Д.Д. — он занимается ремонтом телевизоров, самым дорогостоящим направлением. Алексеев А.А. лидирует по количеству заказов.

### Витрина 2: неисправности по видам устройств

```
device_type                fault_type  orders_count  avg_repair_cost  total_revenue  avg_part_cost
  Компьютер  Аппаратная неисправность             2           3400.0         6800.0         1250.0
    Ноутбук Программная неисправность             2           3400.0         6800.0         1600.0
    Ноутбук  Механическое повреждение             1           2800.0         2800.0          950.0
    Планшет  Механическое повреждение             1           2200.0         2200.0          800.0
    Планшет  Аппаратная неисправность             1           5500.0         5500.0         3100.0
   Смартфон Программная неисправность             2           1350.0         2700.0            0.0
   Смартфон  Аппаратная неисправность             2           5000.0        10000.0         2150.0
   Смартфон  Механическое повреждение             1           4200.0         4200.0          350.0
  Телевизор  Аппаратная неисправность             2          14400.0        28800.0         9600.0
```

Телевизоры — самый дорогой вид ремонта (средний чек 14 400 руб.). Программные неисправности смартфонов самые дешёвые (1 350 руб.) и не требуют запчастей.

---

## Шаг 7. Постановка на расписание

Для автоматического обновления витрин каждый час задача зарегистрирована в Планировщике задач Windows:

```powershell
$dbtPath     = "C:\Users\admin\AppData\Local\Programs\Python\Python312\Scripts\dbt.exe"
$projectPath = "C:\Users\admin\Downloads\repair_dbt"

$action  = New-ScheduledTaskAction -Execute $dbtPath -Argument "run --profiles-dir ." -WorkingDirectory $projectPath
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -Once -At (Get-Date)
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "dbt_repair_hourly" -Description "Hourly dbt run for repair service DWH" -Force
```

```
TaskPath                                       TaskName                          State
--------                                       --------                          -----
\                                              dbt_repair_hourly                 Ready
```

Задача `dbt_repair_hourly` зарегистрирована со статусом **Ready** и запускается каждый час.

---

## Вывод

В ходе работы развёрнут проект dbt для автоматизированной обработки данных сервиса по ремонту техники. В качестве хранилища использована встроенная аналитическая СУБД DuckDB, не требующая отдельного сервера.

Разработаны три модели: staging-модель с валидацией данных по шести сущностям предметной области и две аналитические витрины — по эффективности инженеров и по распределению неисправностей по типам устройств. Валидация корректно исключила запись с отрицательной стоимостью запчасти. Все модели выполнены без ошибок (PASS=3). Обновление витрин настроено через Планировщик задач Windows с интервалом один час.
