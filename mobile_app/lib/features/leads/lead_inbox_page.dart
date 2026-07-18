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

  @override
  void initState() {
    super.initState();
    _leads = _load();
  }

  Future<List<LeadItem>> _load() => widget.api.listLeads(
        actorProfile: widget.actorProfile,
      );

  Future<void> _refresh() async {
    setState(() {
      _leads = _load();
    });
    await _leads;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заказы'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<LeadItem>>(
        future: _leads,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _LeadLoadError(onRetry: _refresh, error: snapshot.error);
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
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final lead = leads[index];
                return _LeadCard(
                  lead: lead,
                  onTap: () async {
                    final changed = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _LeadDetailSheet(
                        api: widget.api,
                        actorProfile: widget.actorProfile,
                        lead: lead,
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
                  Icon(Icons.schedule_outlined, size: 16, color: theme.colorScheme.outline),
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
  late final TextEditingController _reply;
  late final TextEditingController _title;
  late final TextEditingController _price;
  late final TextEditingController _days;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lead = widget.lead;
    _reply = TextEditingController(text: _lead.draftReply);
    _title = TextEditingController(text: _lead.proposalTitle);
    _price = TextEditingController(text: _lead.proposalPriceRub?.toString() ?? '');
    _days = TextEditingController(text: _lead.proposalDays?.toString() ?? '');
  }

  @override
  void dispose() {
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
    await _run(() => widget.api.editLead(
          actorProfile: widget.actorProfile,
          leadId: _lead.id,
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
        const SnackBar(content: Text('Заполни текст, название, цену и срок перед одобрением')),
      );
      return;
    }
    await _run(() => widget.api.approveLead(
          actorProfile: widget.actorProfile,
          leadId: _lead.id,
        ),
    );
  }

  Future<void> _reject() async {
    await _run(() => widget.api.rejectLead(
          actorProfile: widget.actorProfile,
          leadId: _lead.id,
        ),
    );
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
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
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
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _LeadStatusChip(status: lead.status),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: lead.sourceUrl.isEmpty ? null : _openSource,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Открыть заказ на Kwork'),
                    ),
                    _InfoBlock(label: 'Кратко', text: lead.summary),
                    _InfoBlock(label: 'Техническое задание', text: lead.rawBrief),
                    _InfoBlock(label: 'Вложения', text: lead.attachmentReport),
                    if (lead.lastError.trim().isNotEmpty)
                      _InfoBlock(label: 'Ошибка отправки', text: lead.lastError, error: true),
                    const SizedBox(height: 20),
                    Text('Отклик', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
  const _InfoBlock({required this.label, required this.text, this.error = false});
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
          Text(label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
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
