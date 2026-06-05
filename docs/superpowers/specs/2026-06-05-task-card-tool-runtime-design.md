# ТЗ: стабильная система ИИ-карточка через Task Card Tool Runtime

Дата: 2026-06-05

## 1. Цель

Сделать карточку задачи реальным рабочим объектом для агента, а не текстом в
промпте. Агент должен уметь читать карточку, писать в нее, задавать вопросы,
обновлять чеклисты, прикреплять файлы и двигать статус через гарантированные
операции приложения.

Текущий подход с `TASK_CARD_ACTIONS_JSON` недостаточен: агент может не понять
инструкцию, проигнорировать формат или считать, что он работает только с файлами
проекта. Новый основной механизм - инструмент карточки задачи. JSON-блок остается
только аварийным fallback.

## 2. Принцип

Карточка задачи должна быть доступна агенту как инструмент среды, так же как
workspace-файлы доступны через bridge.

Основное правило:

- агент не "думает" о карточке по промпту;
- агент вызывает операции `task_card.*`;
- приложение и backend сами применяют изменения;
- права проверяются до применения каждого действия;
- все действия пишутся в activity/audit.

## 3. Роли компонентов

### Mobile app

- показывает вкладку `Агент` в карточке;
- запускает или подключает агентскую сессию;
- получает policy ticket;
- показывает прогресс, вопросы агента, комментарии и артефакты;
- локально применяет оптимистичные изменения только после подтвержденного
  ответа backend/bridge;
- скрывает AI/workspace для пользователей без прав.

### Backend

- является источником прав;
- выдает `policy_ticket`;
- хранит и применяет операции карточки;
- проверяет версию карточки, права, workspace и режим агента;
- записывает audit;
- возвращает свежий snapshot карточки после каждой операции.

### CodeWhale bridge

- принимает команды от mobile app и агентской сессии;
- проверяет `policy_ticket`;
- прокидывает агенту tool/CLI для работы с карточкой;
- читает файлы workspace для прикрепления к карточке;
- запрещает команды вне policy.

### Agent runtime

- получает обязательный skill `family-task-card`;
- обязан начать работу с `task_card.read`;
- работает с карточкой через tool/CLI;
- завершает работу через `task_card.finish`;
- при нехватке данных использует `task_card.question.ask`, а не пишет вопрос
  только в агентский чат.

## 4. Task Card Tool Runtime

Нужно реализовать набор операций `task_card.*`.

### 4.1. `task_card.read`

Возвращает актуальный snapshot карточки.

Поля:

- `task.id`;
- `task.title`;
- `task.details`;
- `task.workflow_status`;
- `task.priority`;
- `task.project_id`;
- `task.group_id`;
- `task.due_date`;
- `task.assignees`;
- `task.version`;
- `workspace.id`;
- `policy.mode`;
- `policy.allowed_task_ops`;
- `comments[]`;
- `checklists[]`;
- `attachments[]`;
- `activity[]`;
- `agent_sessions[]`;
- `open_questions[]`.

Snapshot должен содержать id комментариев, чеклистов, пунктов и вложений, чтобы
агент мог адресно обновлять конкретные элементы.

### 4.2. `task_card.comment.add`

Добавляет комментарий агента в карточку.

Параметры:

- `text`;
- `attachment_ids`, опционально;
- `reply_to_comment_id`, опционально;
- `visibility`, по умолчанию `project`.

Права:

- `tasks.comment`;
- `ai.write_task_comments`.

### 4.3. `task_card.question.ask`

Создает вопрос агента прямо в карточке.

Параметры:

- `text`;
- `blocking`, bool;
- `related_checklist_id`, опционально;
- `related_attachment_id`, опционально.

Поведение:

- вопрос отображается в карточке отдельным блоком `Вопросы агента`;
- если `blocking=true`, агентская сессия получает статус `blocked`;
- задача остается в `В работе`;
- пользователь отвечает в карточке;
- ответ добавляется в комментарии и закрывает вопрос;
- агент после `task_card.refresh` видит ответ и может продолжить.

### 4.4. `task_card.checklist.create`

Создает новый чеклист.

Параметры:

- `title`;
- `items[]`;
- `reason`, опционально.

Права:

- `tasks.edit`;
- `ai.manage_checklists`.

### 4.5. `task_card.checklist.item_add`

Добавляет пункт в существующий чеклист.

Параметры:

- `checklist_id`;
- `text`.

### 4.6. `task_card.checklist.item_done`

Отмечает пункт как выполненный.

Параметры:

- `checklist_id`;
- `item_id`;
- `done`;
- `note`, опционально.

### 4.7. `task_card.attachment.add_from_workspace`

Прикрепляет файл из workspace к карточке.

Параметры:

- `path`;
- `caption`;
- `kind`, опционально;
- `comment_text`, опционально.

Поведение:

- bridge проверяет, что путь внутри разрешенного workspace;
- bridge читает файл;
- backend/mobile получает bytes/base64, `mime_type`, `size`;
- вложение добавляется в карточку;
- если указан `comment_text`, создается комментарий с привязанным вложением.

### 4.8. `task_card.status.set`

Меняет статус карточки.

Параметры:

- `status`: `todo`, `in_progress`, `in_review`, `done`, `archive`;
- `reason`;
- `confidence`, опционально.

Права и ограничения:

- `tasks.change_status`;
- `ai.change_task_status`;
- `executor` может переводить `todo -> in_progress -> in_review`;
- `reviewer` может переводить `in_review -> in_progress` или предлагать `done`;
- `done` без подтверждения человека разрешен только `superadmin` или явно
  включенный режим;
- `archive` агенту запрещен по умолчанию.

### 4.9. `task_card.refresh`

Возвращает свежий snapshot карточки. Используется после ответов пользователя,
внешних изменений или конфликтов версии.

### 4.10. `task_card.finish`

Завершает агентскую работу по задаче.

Параметры:

- `summary`;
- `result_status`: `needs_user_answer`, `blocked`, `ready_for_review`,
  `done_proposed`, `failed`;
- `changed_files[]`;
- `attachment_ids[]`;
- `next_steps[]`, опционально.

Поведение:

- создает итоговый комментарий;
- обновляет agent session status;
- если `ready_for_review`, переводит задачу в `in_review`;
- если `blocked`, оставляет `in_progress` и показывает блокер;
- если `failed`, пишет диагностируемую ошибку.

## 5. Протокол запуска из карточки

1. Mobile сохраняет текущий draft карточки.
2. Mobile синхронизирует карточку с backend.
3. Mobile запрашивает `/agent/ticket`.
4. Backend возвращает policy ticket с:
   - `actor_profile`;
   - `task_id`;
   - `workspace_id`;
   - `agent_session_id`;
   - `mode`;
   - `allowed_task_ops`;
   - `allowed_bridge_commands`;
   - `allowed_plugins`;
   - `expires_at`;
   - signature.
5. Mobile создает bridge session.
6. Bridge стартует worker с task-card tool/CLI.
7. Первый системный шаг агента: `/skill family-task-card`.
8. Второй системный шаг: обязательная команда `task_card.read`.
9. Только после успешного `read` агент получает пользовательскую цель.
10. Если агент не вызывает `task_card.finish`, сессия получает
    `protocol_failed`.

## 6. Skill `family-task-card`

Skill должен быть коротким и жестким.

Смысл skill:

- карточка задачи является главным рабочим объектом;
- нельзя искать карточку в репозитории;
- нельзя считать работу завершенной без `task_card.finish`;
- если данных не хватает, нужно вызвать `task_card.question.ask`;
- все изменения карточки делаются только через `task_card.*`;
- файлы и скрины прикрепляются через `task_card.attachment.add_from_workspace`.

Skill не должен быть единственной защитой. Он только помогает агенту правильно
использовать реальные инструменты.

## 7. CLI или MCP

Минимальный надежный вариант для текущей архитектуры - CLI внутри workspace:

```powershell
family-task-card read
family-task-card comment add --text "..."
family-task-card question ask --text "Нужен макет формы" --blocking
family-task-card checklist create --title "Проверка" --item "Открыть экран"
family-task-card checklist item-done --checklist-id ... --item-id ...
family-task-card attachment add-from-workspace --path reports/result.md --caption "Отчет"
family-task-card status set in_review --reason "Готово к проверке"
family-task-card finish --summary "Формы проверены" --result-status ready_for_review
```

Позже можно заменить CLI на MCP tool, но первый рабочий релиз проще и быстрее
сделать через CLI, потому что агент уже умеет запускать команды в workspace.

CLI должен читать контекст из env:

- `FAMILY_TASK_CARD_API_URL`;
- `FAMILY_TASK_CARD_TICKET`;
- `FAMILY_TASK_CARD_WORKSPACE_ID`;
- `FAMILY_TASK_CARD_SESSION_ID`.

## 8. Backend endpoints

Нужны новые endpoints:

- `POST /agent/task-card/read`;
- `POST /agent/task-card/comment`;
- `POST /agent/task-card/question`;
- `POST /agent/task-card/checklist`;
- `POST /agent/task-card/checklist-item`;
- `POST /agent/task-card/attachment`;
- `POST /agent/task-card/status`;
- `POST /agent/task-card/finish`;
- `POST /agent/task-card/refresh`.

Каждый endpoint:

- принимает `policy_ticket`;
- проверяет подпись и срок;
- проверяет `task_id`, `workspace_id`, `agent_session_id`;
- проверяет конкретную операцию в `allowed_task_ops`;
- применяет изменение атомарно;
- возвращает свежий snapshot карточки.

## 9. Версии и конфликты

У карточки должна быть версия.

Каждая write-операция отправляет `expected_version`.

Если версия устарела:

- backend возвращает `409`;
- агент вызывает `task_card.refresh`;
- агент повторяет действие с учетом свежего snapshot.

Это защищает от ситуации, когда человек и агент одновременно меняют чеклист или
статус.

## 10. UI карточки

Во вкладке `Агент` нужно показывать не статичный рекламный блок возможностей, а
рабочий инструмент:

- текущая связанная сессия;
- режим агента;
- workspace;
- разрешенные операции;
- кнопки `Новый агент`, `Подключить чат`, `Остановить`, `Продолжить`;
- очередь последних операций;
- блок `Вопросы агента`;
- блок `Артефакты агента`;
- блок `Ошибки протокола`.

Во вкладке работы карточки:

- комментарии агента помечаются как `Агент`;
- вложения агента показываются как обычные файлы/скрины;
- вопросы агента можно быстро отвечать прямо в карточке;
- статусные изменения агента видны в activity.

## 11. Поведение при ошибках

### Агент не прочитал карточку

Если после запуска нет успешного `task_card.read`, сессия получает статус
`protocol_failed`. UI показывает: `Агент не получил карточку задачи`.

### Агент не завершил работу

Если нет `task_card.finish`, сессия получает статус `incomplete`.
Карточка не переводится в `in_review` автоматически.

### Нет прав

Операция возвращает `403` с русским текстом причины. UI показывает событие
`agent_permission_denied`.

### Файл не найден

`attachment.add_from_workspace` возвращает диагностируемую ошибку:
`Файл не найден в рабочем пространстве: <path>`.

### Карточка изменилась

Операция возвращает `409`. Агент обязан вызвать `refresh`.

## 12. Fallback

`TASK_CARD_ACTIONS_JSON` можно оставить на один переходный релиз, но:

- он не должен быть основным механизмом;
- UI должен помечать такие изменения как `fallback`;
- если tool-runtime доступен, JSON-фоллбек не используется;
- после стабилизации tool-runtime fallback можно удалить.

## 13. Минимальный MVP

Первый релиз должен включать:

1. `task_card.read`;
2. `task_card.comment.add`;
3. `task_card.question.ask`;
4. `task_card.checklist.create`;
5. `task_card.checklist.item_done`;
6. `task_card.attachment.add_from_workspace`;
7. `task_card.status.set`;
8. `task_card.finish`;
9. CLI `family-task-card`;
10. skill `family-task-card`;
11. запуск агента из карточки с обязательным `read`;
12. e2e-тест сценария:
    - агент читает карточку;
    - задает вопрос;
    - добавляет комментарий;
    - создает чеклист;
    - прикрепляет отчет;
    - переводит в `in_review`;
    - завершает через `finish`.

## 14. Definition of Done

Система считается рабочей, когда:

- агент может получить карточку через `task_card.read` без зависимости от
  текста промпта;
- агент может писать в карточку через операции, а не через финальный JSON;
- каждое действие проверяется policy ticket;
- вопрос агента отображается в карточке и может быть закрыт ответом человека;
- файлы и скрины из workspace становятся реальными вложениями карточки;
- статус карточки меняется только разрешенной операцией;
- при ошибке видно, какая операция не прошла и почему;
- есть unit и widget tests;
- есть хотя бы один интеграционный тест bridge/backend/CLI;
- изменения закоммичены и запушены.

