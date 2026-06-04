import 'dart:convert';

class AgentLaunchPlan {
  const AgentLaunchPlan({required this.steps});

  final List<AgentLaunchStep> steps;

  static AgentLaunchPlan build({
    required String contextPrompt,
    required List<String> selectedCommandValues,
    required List<Map<String, dynamic>> commands,
  }) {
    final commandByValue = <String, Map<String, dynamic>>{};
    for (final command in commands) {
      final value = _valueOf(command);
      if (value.isEmpty) {
        continue;
      }
      commandByValue[value] = command;
    }

    final seen = <String>{};
    final steps = <AgentLaunchStep>[];
    for (final value in selectedCommandValues) {
      final command = commandByValue[value.trim()];
      if (command == null || !seen.add(value.trim())) {
        continue;
      }
      steps.add(
        AgentLaunchStep(
          label: _labelOf(command),
          text: _valueOf(command),
          kind: AgentLaunchStepKind.command,
        ),
      );
    }

    steps.add(
      AgentLaunchStep(
        label: 'Работа по задаче',
        text: _taskPrompt(contextPrompt),
        kind: AgentLaunchStepKind.taskPrompt,
      ),
    );
    return AgentLaunchPlan(steps: steps);
  }

  static String _taskPrompt(String contextPrompt) {
    final prompt = contextPrompt.trim();
    final instructions = [
      'Обязательно учитывай описание, комментарии, чеклисты и вложения карточки.',
      'Если для отчета нужны новые списки, пункты, файлы или скриншоты, создай их в воркспейсе.',
      'В конце ответа верни блок TASK_CARD_ACTIONS_JSON с действиями для карточки.',
      'Формат: {"comments":["итог"],"checklists":[{"title":"Проверка","items":["пункт"]}],"attachments":[{"path":"vision/screen.png","filename":"screen.png","caption":"скрин"}]}.',
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

enum AgentLaunchStepKind { command, taskPrompt }

class AgentTaskActions {
  const AgentTaskActions({
    this.comments = const [],
    this.checklists = const [],
    this.attachments = const [],
  });

  final List<String> comments;
  final List<AgentChecklistDraft> checklists;
  final List<AgentAttachmentDraft> attachments;

  bool get isEmpty =>
      comments.isEmpty && checklists.isEmpty && attachments.isEmpty;

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
