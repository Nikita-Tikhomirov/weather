import 'dart:convert';

class AgentLaunchPlanLabels {
  const AgentLaunchPlanLabels({
    this.taskCard = 'Task card',
    this.taskCardRead = 'Read task card',
    this.appContext = 'App context',
    this.taskWork = 'Task work',
    this.continueWork = 'Continue work',
  });

  final String taskCard;
  final String taskCardRead;
  final String appContext;
  final String taskWork;
  final String continueWork;
}

class AgentLaunchPlan {
  const AgentLaunchPlan({required this.steps});

  final List<AgentLaunchStep> steps;

  static AgentLaunchPlan build({
    required String contextPrompt,
    required List<String> selectedCommandValues,
    required List<Map<String, dynamic>> commands,
    AgentLaunchPlanLabels labels = const AgentLaunchPlanLabels(),
  }) {
    final steps = _baseSteps(
      selectedCommandValues: selectedCommandValues,
      commands: commands,
      labels: labels,
    );
    steps.add(
      AgentLaunchStep(
        label: labels.taskWork,
        text: _taskPrompt(contextPrompt),
        kind: AgentLaunchStepKind.taskPrompt,
      ),
    );
    return AgentLaunchPlan(steps: steps);
  }

  static AgentLaunchPlan buildContinuation({
    required String contextPrompt,
    required List<String> selectedCommandValues,
    required List<Map<String, dynamic>> commands,
    AgentLaunchPlanLabels labels = const AgentLaunchPlanLabels(),
  }) {
    final steps = _baseSteps(
      selectedCommandValues: selectedCommandValues,
      commands: commands,
      labels: labels,
    );
    steps.add(
      AgentLaunchStep(
        label: labels.continueWork,
        text: _continuationPrompt(contextPrompt),
        kind: AgentLaunchStepKind.taskPrompt,
      ),
    );
    return AgentLaunchPlan(steps: steps);
  }

  static List<AgentLaunchStep> _baseSteps({
    required List<String> selectedCommandValues,
    required List<Map<String, dynamic>> commands,
    required AgentLaunchPlanLabels labels,
  }) {
    final commandByValue = <String, Map<String, dynamic>>{};
    for (final command in commands) {
      final value = _valueOf(command);
      if (value.isEmpty) {
        continue;
      }
      commandByValue[value] = command;
    }

    final seen = <String>{'/skill family-task-card'};
    final steps = <AgentLaunchStep>[
      AgentLaunchStep(
        label: labels.taskCard,
        text: '/skill family-task-card',
        kind: AgentLaunchStepKind.command,
      ),
      AgentLaunchStep(
        label: labels.taskCardRead,
        text:
            'Выполни команду family-task-card read. Изучи snapshot карточки: описание, комментарии, чеклисты, вопросы и вложения. Если команда недоступна или вернула ошибку, остановись и напиши, что карточка задачи недоступна. Не спрашивай подтверждение на перевод карточки: если работа уже готова и нет блокирующего вопроса, используй family-task-card finish --summary "..." --result-status ready_for_review.',
        kind: AgentLaunchStepKind.taskCardRead,
      ),
    ];
    for (final value in selectedCommandValues) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      final command = commandByValue[trimmed];
      if (command == null && commands.isNotEmpty) {
        continue;
      }
      steps.add(
        AgentLaunchStep(
          label: command == null ? trimmed : _labelOf(command),
          text: command == null ? trimmed : _valueOf(command),
          kind: AgentLaunchStepKind.command,
        ),
      );
    }

    steps.add(
      AgentLaunchStep(
        label: labels.appContext,
        text: _appContextPrompt,
        kind: AgentLaunchStepKind.appContext,
      ),
    );
    return steps;
  }

  static String _taskPrompt(String contextPrompt) {
    final prompt = contextPrompt.trim();
    final instructions = [
      'Обязательно учитывай описание, комментарии, чеклисты и вложения карточки.',
      'Если нужно добавить проверку или подпункт, сначала используй существующий чеклист из family-task-card read: family-task-card checklist item-add --checklist-id "<id>" --text "...".',
      'Не создавай новый чеклист, если в карточке уже есть подходящий чеклист; новый создавай только для отдельного нового блока работ.',
      'Если для отчета нужны новые файлы или скриншоты, создай их в воркспейсе.',
      'Основной способ обновления карточки - команда family-task-card: comment add, checklist item-add, checklist create, attachment add-from-workspace, status set, finish.',
      'Не спрашивай подтверждение на перевод карточки. Если работа выполнена и не нужен ответ пользователя, обязательно сразу выполни: family-task-card finish --summary "<краткий итог>" --result-status ready_for_review.',
      'Если без ответа пользователя продолжать нельзя, не спрашивай обычным сообщением; задай блокирующий вопрос через family-task-card question ask --text "..." --blocking.',
      'Не пиши пользователю "перенести в ready_for_review?", "перевести на проверку?" или похожие вопросы.',
      'TASK_CARD_ACTIONS_JSON разрешен только если команда family-task-card недоступна.',
      'Формат: {"status":"in_review","comments":["итог"],"checklists":[{"title":"Проверка","items":["пункт"]}],"attachments":[{"path":"vision/screen.png","filename":"screen.png","caption":"скрин"}]}.',
      'Для движения карточки укажи status/workflow_status/move_to: todo, in_progress, in_review, done или archive.',
      'Для созданных отчетов и скриншотов обязательно указывай путь в attachments, files или screenshots, чтобы мобильная карточка прикрепила их автоматически.',
      'Не выдумывай файлы: в attachments указывай только реально созданные или найденные пути.',
    ].join('\n');
    if (prompt.isEmpty) {
      return [
        'Выполни задачу по карточке.',
        instructions,
      ].join('\n');
    }
    return [
      'Выполни задачу по карточке.',
      instructions,
      '',
      prompt,
    ].join('\n');
  }

  static String _continuationPrompt(String contextPrompt) {
    final prompt = contextPrompt.trim();
    final base = [
      'Продолжи работу по этой же карточке задачи.',
      'Сначала учитывай новые комментарии, чеклисты, вопросы, вложения и текущий статус из family-task-card read.',
      'Не создавай новый агентский чат и не начинай задачу заново: продолжай этот же ход работы.',
      'Если нужно добавить пункт проверки, допиши его в существующий чеклист через family-task-card checklist item-add --checklist-id "<id>" --text "..."; не создавай новый чеклист без необходимости.',
      'После правок снова обнови карточку через family-task-card: добавь комментарий-итог, файлы/скриншоты отчета и переведи в in_review.',
      'Не спрашивай подтверждение на перевод карточки. Если работа выполнена и не нужен ответ пользователя, обязательно сразу выполни: family-task-card finish --summary "<краткий итог>" --result-status ready_for_review.',
      'Если без ответа пользователя продолжать нельзя, не спрашивай обычным сообщением; задай блокирующий вопрос через family-task-card question ask --text "..." --blocking.',
      'Не пиши пользователю "перенести в ready_for_review?", "перевести на проверку?" или похожие вопросы.',
      'Если карточка уже в done или archive, не выполняй новые правки и напиши, что задача закрыта.',
    ];
    if (prompt.isEmpty) {
      return base.join('\n');
    }
    return [
      ...base,
      '',
      prompt,
    ].join('\n');
  }

  static String _valueOf(Map<String, dynamic> command) {
    return (command['value'] ?? '').toString().trim();
  }

  static String _labelOf(Map<String, dynamic> command) {
    final label = (command['label'] ?? '').toString().trim();
    if (label.isNotEmpty) {
      return label;
    }
    return _valueOf(command);
  }
}

const _appContextPrompt = '''
Системный контекст Family Todo.
Ты запущен из мобильного приложения Family Todo из карточки задачи.
Карточка задачи не файл в проекте: читай и обновляй ее через команду family-task-card.
Не ищи карточку задачи в репозитории и не проси пользователя прислать ее отдельно.
Работай в текущем CodeWhale workspace только для файлов проекта, отчетов, скриншотов и анализа.
Комментарии, вопросы, чеклисты, статусы и вложения карточки меняй через family-task-card.
Не спрашивай подтверждение на перевод карточки. Готовая работа без блокера должна сама завершаться через family-task-card finish --summary "..." --result-status ready_for_review.
Если нужен ответ пользователя, задавай его только через family-task-card question ask --text "..." --blocking.
TASK_CARD_ACTIONS_JSON используй только как аварийный fallback, если команда family-task-card недоступна.
''';

class AgentLaunchStep {
  const AgentLaunchStep({
    required this.label,
    required this.text,
    required this.kind,
  });

  final String label;
  final String text;
  final AgentLaunchStepKind kind;
}

enum AgentLaunchStepKind { command, taskCardRead, appContext, taskPrompt }

class AgentTaskActions {
  const AgentTaskActions({
    this.status = '',
    this.comments = const [],
    this.checklists = const [],
    this.attachments = const [],
  });

  final String status;
  final List<String> comments;
  final List<AgentChecklistDraft> checklists;
  final List<AgentAttachmentDraft> attachments;

  bool get isEmpty =>
      status.trim().isEmpty &&
      comments.isEmpty &&
      checklists.isEmpty &&
      attachments.isEmpty;

  static AgentTaskActions parse(String text) {
    final jsonText = _extractJson(text);
    if (jsonText.isEmpty) {
      return const AgentTaskActions();
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        return const AgentTaskActions();
      }
      final root = decoded['task_card_actions'] is Map
          ? Map<String, dynamic>.from(decoded['task_card_actions'] as Map)
          : Map<String, dynamic>.from(decoded);
      return AgentTaskActions(
        status: _statusOf(root),
        comments: _stringList(_mergedList(root, const ['comments'])),
        checklists: _checklists(
          _mergedList(root, const ['checklists', 'lists', 'new_checklists']),
        ),
        attachments: _attachments(
          _mergedList(root, const [
            'attachments',
            'files',
            'screenshots',
          ]),
        ),
      );
    } catch (_) {
      return const AgentTaskActions();
    }
  }

  static String stripActionsBlock(String text) {
    return text
        .replaceAll(
          RegExp(r'TASK_CARD_ACTIONS_JSON\s*:\s*```json[\s\S]*?```'),
          '',
        )
        .replaceAll(
          RegExp(r'TASK_CARD_ACTIONS_JSON\s*:\s*\{[\s\S]*\}\s*$'),
          '',
        )
        .trim();
  }

  static String _extractJson(String text) {
    final marker = text.indexOf('TASK_CARD_ACTIONS_JSON');
    if (marker < 0) {
      return '';
    }
    final tail = text.substring(marker);
    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(tail);
    if (fenced != null) {
      return fenced.group(1)?.trim() ?? '';
    }
    final start = tail.indexOf('{');
    final end = tail.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return '';
    }
    return tail.substring(start, end + 1).trim();
  }

  static List<Object?> _mergedList(
    Map<String, dynamic> root,
    List<String> keys,
  ) {
    final result = <Object?>[];
    for (final key in keys) {
      final raw = root[key];
      if (raw is List) {
        result.addAll(raw);
      } else if (raw != null) {
        result.add(raw);
      }
    }
    return result;
  }

  static String _statusOf(Map<String, dynamic> root) {
    for (final key in const [
      'status',
      'workflow_status',
      'workflowStatus',
      'move_to',
      'moveTo',
      'state',
    ]) {
      final value = root[key]?.toString().trim() ?? '';
      final normalized = _normalizeStatus(value);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    final task = root['task'];
    if (task is Map) {
      return _statusOf(Map<String, dynamic>.from(task));
    }
    return '';
  }

  static String _normalizeStatus(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) {
      return '';
    }
    final compact = lower
        .replaceAll(RegExp(r'[\s./\\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    switch (compact) {
      case 'todo':
      case 'to_do':
      case 'backlog':
      case 'new':
      case 'к_выполнению':
      case 'новая':
        return 'todo';
      case 'in_progress':
      case 'progress':
      case 'doing':
      case 'work':
      case 'в_работе':
        return 'in_progress';
      case 'in_review':
      case 'review':
      case 'qa':
      case 'на_проверке':
      case 'проверка':
        return 'in_review';
      case 'done':
      case 'complete':
      case 'completed':
      case 'ready':
      case 'готово':
      case 'выполнено':
        return 'done';
      case 'archive':
      case 'archived':
      case 'архив':
        return 'archive';
      default:
        return '';
    }
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.map(_textOf).where((item) => item.isNotEmpty).toList();
  }

  static String _textOf(Object? raw) {
    if (raw is Map) {
      for (final key in const ['text', 'title', 'label', 'name', 'value']) {
        final value = raw[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          return value;
        }
      }
      return '';
    }
    return raw?.toString().trim() ?? '';
  }

  static List<AgentChecklistDraft> _checklists(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return AgentChecklistDraft(
        title: (map['title'] ?? '').toString().trim(),
        items: _stringList(map['items']),
      );
    }).where((item) {
      return item.title.isNotEmpty || item.items.isNotEmpty;
    }).toList();
  }

  static List<AgentAttachmentDraft> _attachments(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .map((item) {
          final map = item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{'path': item};
          return AgentAttachmentDraft(
            path: (map['path'] ??
                    map['asset_url'] ??
                    map['assetUrl'] ??
                    map['file_path'] ??
                    map['url'] ??
                    '')
                .toString()
                .trim(),
            filename: (map['filename'] ?? map['name'] ?? '').toString().trim(),
            caption: (map['caption'] ?? '').toString().trim(),
            mimeType:
                (map['mime_type'] ?? map['mimeType'] ?? '').toString().trim(),
          );
        })
        .where((item) => item.path.isNotEmpty || item.filename.isNotEmpty)
        .toList();
  }
}

class AgentChecklistDraft {
  const AgentChecklistDraft({required this.title, required this.items});

  final String title;
  final List<String> items;
}

class AgentAttachmentDraft {
  const AgentAttachmentDraft({
    required this.path,
    required this.filename,
    required this.caption,
    required this.mimeType,
  });

  final String path;
  final String filename;
  final String caption;
  final String mimeType;
}
