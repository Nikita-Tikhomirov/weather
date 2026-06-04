# ТЗ: задачи как центр управления агентами и правами

## Цель

Связать таск-менеджер, мессенджер и воркспейсы так, чтобы задача стала рабочим центром управления агентом:

- мессенджер живет отдельно и доступен обычным пользователям;
- рабочие разделы, AI и воркспейсы доступны только пользователям с выданными правами;
- доступы к воркспейсам выдает и отзывает только Никита, телефон `+79679812438`, роль `superadmin`;
- из задачи можно подключить существующий агентский чат или создать новый;
- агент получает контекст задачи и может двигать задачу только в рамках policy-ticket.

## Роли и права

Базовые роли:

- `messenger_user`: только мессенджер.
- `workspace_user`: мессенджер, проекты/задачи на чтение, чтение и использование воркспейса, AI.
- `agent_operator`: запуск агента из задачи, запись комментариев/статусов, рабочие агентские плагины.
- `workspace_admin`: расширенные workspace/project/task права без права выдавать доступы.
- `superadmin`: все права, включая `workspaces.grant_access`, `admin.audit`, `ai.autopilot`, `agent.deploy`.

Правило выдачи доступов:

- `workspaces.grant_access` есть только у `superadmin`;
- backend отклоняет grant/revoke от любого другого профиля;
- mobile показывает админ-панель только при `canManageWorkspaceAccess`.

## Task-agent flow

1. Пользователь открывает задачу.
2. Приложение получает `/agent/policy` для `actor_profile + task_id + workspace_id + mode`.
3. Вкладка `Агент` показывает:
   - доступность запуска;
   - режим;
   - плагины;
   - workspace;
   - подключенные agent sessions.
4. При `Новый чат`:
   - задача сохраняется;
   - mobile получает `/agent/ticket`;
   - mobile получает `/agent/context`;
   - mobile создает CodeWhale session с policy-ticket;
   - context pack отправляется первым сообщением агенту;
   - session/event пишутся в backend и в `TaskCollaboration`.
5. При агентском событии backend добавляет:
   - `task_agent_events`;
   - запись в `collaboration.activity`;
   - итоговый комментарий, если пришел summary;
   - статус задачи: запуск -> `in_progress`, запрос ревью -> `in_review`, завершение -> `done`.

## Backend API

Обязательные endpoints:

- `GET /me/access`
- `POST /agent/policy`
- `POST /agent/ticket`
- `POST /agent/context`
- `POST /agent/events`
- `POST /agent/sessions`
- `GET /admin/workspace-access`
- `POST /admin/workspace-access/grant`
- `POST /admin/workspace-access/revoke`
- `GET /admin/audit`

Обязательные таблицы:

- `user_roles`
- `role_capabilities`
- `workspace_access`
- `agent_mode_catalog`
- `agent_plugin_catalog`
- `task_agent_sessions`
- `task_agent_events`
- `agent_policy_tickets`
- `audit_logs`

## Mobile UI

- Весь новый интерфейс на русском.
- Обычный пользователь без workspace/access видит только мессенджер.
- Профиль Никиты показывает блок `Доступы к воркспейсам`.
- Вкладка задачи `Агент` не запускает ничего без policy.
- Воркспейсы из мессенджера открываются только при `workspaces.use`.

## Bridge/tunnel

- CodeWhale bridge команды защищены `policy_ticket`.
- Tunnel в secure mode не пропускает workspace/session команды без валидного ticket.
- Ticket должен разрешать конкретную команду и совпадать по workspace.

## Acceptance criteria

- Никита получает `superadmin` по телефону `79679812438`.
- Обычный пользователь без grant получает только `messenger.use`.
- Grant/revoke workspace access доступен только суперадмину.
- Из задачи можно создать agent session с context pack.
- Agent session и event сохраняются в backend и в `collaboration`.
- Все новые UI-строки на русском.
- Python tests, Dart analyze и Flutter tests проходят.
