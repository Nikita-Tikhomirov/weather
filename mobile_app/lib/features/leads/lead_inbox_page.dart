import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../contracts/lead_api.dart';
import '../../models/lead_models.dart';

class LeadInboxPage extends StatefulWidget {
  const LeadInboxPage({
    super.key,
    required this.api,
    required this.actorProfile,
  });

  final LeadApi api;
  final String actorProfile;

  @override
  State<LeadInboxPage> createState() => _LeadInboxPageState();
}

class _LeadInboxPageState extends State<LeadInboxPage> {
  late Future<List<LeadItem>> _leads;
  late Future<LeadMonitor> _monitor;

  @override
  void initState() {
    super.initState();
    _leads = _load();
    _monitor = _loadMonitor();
  }

  Future<List<LeadItem>> _load() => widget.api.listLeads(
        actorProfile: widget.actorProfile,
      );

  Future<LeadMonitor> _loadMonitor() => widget.api.getMonitor(
        actorProfile: widget.actorProfile,
      );

  Future<void> _refresh() async {
    setState(() {
      _leads = _load();
      _monitor = _loadMonitor();
    });
    await _leads;
  }

  Future<void> _controlMonitor(String command) async {
    try {
      final updated = await widget.api.controlMonitor(
        actorProfile: widget.actorProfile,
        command: command,
      );
      if (!mounted) return;
      setState(() => _monitor = Future.value(updated));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось передать команду: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заказы'),
        actions: [
          IconButton(
            tooltip: 'Создать заказ',
            onPressed: _createLead,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<LeadMonitor>(
            future: _monitor,
            builder: (context, snapshot) {
              final monitor = snapshot.data;
              return _MonitorControls(
                monitor: monitor,
                onCommand: _controlMonitor,
              );
            },
          ),
          Expanded(
            child: FutureBuilder<List<LeadItem>>(
              future: _leads,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _LeadLoadError(
                      onRetry: _refresh, error: snapshot.error);
                }
                final leads = snapshot.data ?? const <LeadItem>[];
                if (leads.isEmpty) {
                  return const _LeadEmptyState();
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: leads.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final lead = leads[index];
                      return _LeadCard(
                        lead: lead,
                        onTap: () async {
                          LeadItem current = lead;
                          try {
                            current = await widget.api.getLead(
                              actorProfile: widget.actorProfile,
                              leadId: lead.id,
                            );
                          } catch (_) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Открыта сохраненная версия карточки')),
                            );
                          }
                          if (!context.mounted) return;
                          final changed = await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => _LeadDetailSheet(
                              api: widget.api,
                              actorProfile: widget.actorProfile,
                              lead: current,
                            ),
                          );
                          if (changed == true && mounted) {
                            await _refresh();
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createLead() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LeadCreateSheet(
        api: widget.api,
        actorProfile: widget.actorProfile,
      ),
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }
}

class _MonitorControls extends StatelessWidget {
  const _MonitorControls({required this.monitor, required this.onCommand});

  final LeadMonitor? monitor;
  final ValueChanged<String> onCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = monitor?.isRunning == true
        ? 'Мониторинг включен'
        : 'Мониторинг остановлен';
    final detail = monitor?.lastSeenAt == null
        ? 'ПК пока не на связи'
        : 'ПК на связи: ${_leadTime(monitor!.lastSeenAt!)}';
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(detail, style: theme.textTheme.labelMedium),
          if ((monitor?.lastError ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(monitor!.lastError,
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => onCommand('scan'),
                icon: const Icon(Icons.radar_outlined),
                label: const Text('Сканировать сейчас'),
              ),
              OutlinedButton.icon(
                onPressed: monitor?.isRunning == true
                    ? null
                    : () => onCommand('start'),
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Старт'),
              ),
              OutlinedButton.icon(
                onPressed: monitor?.isRunning == false
                    ? null
                    : () => onCommand('stop'),
                icon: const Icon(Icons.stop_outlined),
                label: const Text('Стоп'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead, required this.onTap});

  final LeadItem lead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = <String>[
      if (lead.offerCount != null) '${lead.offerCount} откл.',
      if (lead.proposalPriceRub != null) '${lead.proposalPriceRub} руб.',
      if (lead.proposalDays != null) '${lead.proposalDays} дн.',
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      lead.title.isEmpty ? 'Заказ без названия' : lead.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _LeadStatusChip(status: lead.status),
                ],
              ),
              if (lead.summary.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  lead.summary.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_outlined,
                      size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _leadTime(lead.updatedAt),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta.join('  ·  '),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              if (lead.lastError.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  lead.lastError.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadCreateSheet extends StatefulWidget {
  const _LeadCreateSheet({required this.api, required this.actorProfile});

  final LeadApi api;
  final String actorProfile;

  @override
  State<_LeadCreateSheet> createState() => _LeadCreateSheetState();
}

class _LeadCreateSheetState extends State<_LeadCreateSheet> {
  final _taskTitle = TextEditingController();
  final _sourceUrl = TextEditingController();
  final _brief = TextEditingController();
  final _reply = TextEditingController();
  final _proposalTitle = TextEditingController();
  final _price = TextEditingController();
  final _days = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _taskTitle.dispose();
    _sourceUrl.dispose();
    _brief.dispose();
    _reply.dispose();
    _proposalTitle.dispose();
    _price.dispose();
    _days.dispose();
    super.dispose();
  }

  int? _number(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value != null && value > 0 ? value : null;
  }

  Future<void> _create() async {
    if (_taskTitle.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажи название задачи')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.createLead(
        actorProfile: widget.actorProfile,
        title: _taskTitle.text.trim(),
        sourceUrl: _sourceUrl.text.trim(),
        rawBrief: _brief.text.trim(),
        summary: 'Создано вручную',
        draftReply: _reply.text.trim(),
        proposalTitle: _proposalTitle.text.trim(),
        proposalPriceRub: _number(_price),
        proposalDays: _number(_days),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось создать: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .92,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Новый заказ'),
            actions: [
              IconButton(
                tooltip: 'Сохранить заказ',
                onPressed: _saving ? null : _create,
                icon: const Icon(Icons.save_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              TextField(
                controller: _taskTitle,
                enabled: !_saving,
                maxLength: 255,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Название задачи',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sourceUrl,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Ссылка на заказ',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _brief,
                enabled: !_saving,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Техническое задание',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reply,
                enabled: !_saving,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Черновик отклика',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _proposalTitle,
                enabled: !_saving,
                maxLength: 70,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Название заказа в отклике',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _price,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Цена, руб.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _days,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Срок, дни',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _create,
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('Создать карточку'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadDetailSheet extends StatefulWidget {
  const _LeadDetailSheet({
    required this.api,
    required this.actorProfile,
    required this.lead,
  });

  final LeadApi api;
  final String actorProfile;
  final LeadItem lead;

  @override
  State<_LeadDetailSheet> createState() => _LeadDetailSheetState();
}

class _LeadDetailSheetState extends State<_LeadDetailSheet> {
  late LeadItem _lead;
  late final TextEditingController _taskTitle;
  late final TextEditingController _sourceUrl;
  late final TextEditingController _brief;
  late final TextEditingController _reply;
  late final TextEditingController _title;
  late final TextEditingController _price;
  late final TextEditingController _days;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lead = widget.lead;
    _taskTitle = TextEditingController(text: _lead.title);
    _sourceUrl = TextEditingController(text: _lead.sourceUrl);
    _brief = TextEditingController(text: _lead.rawBrief);
    _reply = TextEditingController(text: _lead.draftReply);
    _title = TextEditingController(text: _lead.proposalTitle);
    _price =
        TextEditingController(text: _lead.proposalPriceRub?.toString() ?? '');
    _days = TextEditingController(text: _lead.proposalDays?.toString() ?? '');
  }

  @override
  void dispose() {
    _taskTitle.dispose();
    _sourceUrl.dispose();
    _brief.dispose();
    _reply.dispose();
    _title.dispose();
    _price.dispose();
    _days.dispose();
    super.dispose();
  }

  int? _number(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value != null && value > 0 ? value : null;
  }

  Future<void> _save() async {
    await _run(
      () => widget.api.editLead(
        actorProfile: widget.actorProfile,
        leadId: _lead.id,
        title: _taskTitle.text.trim(),
        sourceUrl: _sourceUrl.text.trim(),
        rawBrief: _brief.text.trim(),
        draftReply: _reply.text.trim(),
        proposalTitle: _title.text.trim(),
        proposalPriceRub: _number(_price),
        proposalDays: _number(_days),
      ),
      closeOnSuccess: false,
    );
  }

  Future<void> _approve() async {
    if (_reply.text.trim().isEmpty ||
        _title.text.trim().isEmpty ||
        _number(_price) == null ||
        _number(_days) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Заполни текст, название, цену и срок перед одобрением')),
      );
      return;
    }
    await _run(
      () => widget.api.approveLead(
        actorProfile: widget.actorProfile,
        leadId: _lead.id,
      ),
    );
  }

  Future<void> _reject() async {
    await _run(
      () => widget.api.rejectLead(
        actorProfile: widget.actorProfile,
        leadId: _lead.id,
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить заказ?'),
        content: const Text(
            'Карточка исчезнет из списка. История действий останется на сервере.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.api.deleteLead(
        actorProfile: widget.actorProfile,
        leadId: _lead.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _run(
    Future<LeadItem> Function() action, {
    bool closeOnSuccess = true,
  }) async {
    setState(() => _saving = true);
    try {
      final updated = await action();
      if (!mounted) return;
      if (closeOnSuccess) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _lead = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Изменения сохранены')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSource() async {
    final uri = Uri.tryParse(_lead.sourceUrl);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть страницу заказа')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = _lead;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .92,
          minChildSize: .55,
          maxChildSize: .98,
          builder: (context, scrollController) => Column(
            children: [
              const SizedBox(height: 10),
              Container(
                height: 4,
                width: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            lead.title,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _LeadStatusChip(status: lead.status),
                        IconButton(
                          tooltip: 'Удалить заказ',
                          onPressed: _saving ? null : _delete,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: lead.sourceUrl.isEmpty ? null : _openSource,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Открыть заказ на Kwork'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _taskTitle,
                      enabled: lead.canEdit && !_saving,
                      maxLength: 255,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Название задачи',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _sourceUrl,
                      enabled: lead.canEdit && !_saving,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Ссылка на заказ',
                      ),
                    ),
                    _InfoBlock(label: 'Кратко', text: lead.summary),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _brief,
                      enabled: lead.canEdit && !_saving,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Техническое задание',
                      ),
                    ),
                    _InfoBlock(label: 'Вложения', text: lead.attachmentReport),
                    if (lead.lastError.trim().isNotEmpty)
                      _InfoBlock(
                          label: 'Ошибка отправки',
                          text: lead.lastError,
                          error: true),
                    const SizedBox(height: 20),
                    Text('Отклик',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reply,
                      enabled: lead.canEdit && !_saving,
                      minLines: 6,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Текст отклика',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _title,
                      enabled: lead.canEdit && !_saving,
                      maxLength: 70,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Название заказа',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _price,
                            enabled: lead.canEdit && !_saving,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Цена, руб.',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _days,
                            enabled: lead.canEdit && !_saving,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Срок, дни',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_saving) const LinearProgressIndicator(),
                    if (lead.canEdit) ...[
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Сохранить изменения'),
                      ),
                    ],
                    if (lead.canApprove) ...[
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _saving ? null : _approve,
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Одобрить и отправить с ПК'),
                      ),
                    ],
                    if (lead.canReject) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _saving ? null : _reject,
                        icon: const Icon(Icons.close),
                        label: const Text('Отклонить заказ'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadStatusChip extends StatelessWidget {
  const _LeadStatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => Colors.teal,
      'sending' => Colors.orange,
      'sent' => Colors.green,
      'failed' => Theme.of(context).colorScheme.error,
      'rejected' => Theme.of(context).colorScheme.outline,
      _ => Theme.of(context).colorScheme.primary,
    };
    final label = switch (status) {
      'new' => 'Новый',
      'edited' => 'Изменен',
      'approved' => 'Одобрен',
      'sending' => 'Отправка',
      'sent' => 'Отправлен',
      'failed' => 'Ошибка',
      'rejected' => 'Отклонен',
      _ => status,
    };
    return Chip(
      label: Text(label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      side: BorderSide(color: color.withValues(alpha: .45)),
      backgroundColor: color.withValues(alpha: .08),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock(
      {required this.label, required this.text, this.error = false});
  final String label;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          SelectableText(
            text.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: error ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadEmptyState extends StatelessWidget {
  const _LeadEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_outline, size: 44),
            SizedBox(height: 12),
            Text('Новых заказов пока нет'),
          ],
        ),
      ),
    );
  }
}

class _LeadLoadError extends StatelessWidget {
  const _LeadLoadError({required this.onRetry, required this.error});
  final Future<void> Function() onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text('Не удалось загрузить заказы'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

String _leadTime(String raw) {
  final value = DateTime.tryParse(raw)?.toLocal();
  if (value == null) return 'Время неизвестно';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)} ${two(value.hour)}:${two(value.minute)}';
}
