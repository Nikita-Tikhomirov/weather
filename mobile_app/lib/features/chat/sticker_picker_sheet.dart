import 'package:flutter/material.dart';

import '../../models/chat_models.dart';
import 'sticker_catalog.dart';

class StickerPickerSheet extends StatefulWidget {
  const StickerPickerSheet({
    super.key,
    required this.packs,
    required this.assetUrlResolver,
    required this.onStickerSelected,
  });

  final List<StickerPack> packs;
  final String Function(String rawAssetUrl) assetUrlResolver;
  final Future<void> Function(StickerItem sticker) onStickerSelected;

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _selectedStyleByGroup = {};
  final Map<String, String> _selectedCategoryByGroup = {};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = buildStickerCatalogEntries(
      widget.packs,
      resolveAssetUrl: widget.assetUrlResolver,
    );
    final groups = _groupsFor(entries);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StickerSheetHeader(count: entries.length),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Поиск',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _query = value.trim().toLowerCase());
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: entries.isEmpty
                  ? const _StickerEmptyState()
                  : DefaultTabController(
                      length: groups.length,
                      child: Column(
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabs: [
                              for (final group in groups)
                                Tab(
                                  text:
                                      '${stickerGroupLabel(group)} ${_groupCount(entries, group)}',
                                ),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                for (final group in groups)
                                  _buildGroupView(context, entries, group),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupView(
    BuildContext context,
    List<StickerCatalogEntry> entries,
    String group,
  ) {
    final groupEntries =
        entries.where((entry) => entry.meta.group == group).toList();
    final styles = _stylesFor(groupEntries);
    final requestedStyle = _selectedStyleByGroup[group] ?? 'all';
    final selectedStyle =
        styles.contains(requestedStyle) ? requestedStyle : 'all';
    final styleEntries = selectedStyle == 'all'
        ? groupEntries
        : groupEntries
            .where((entry) => entry.meta.style == selectedStyle)
            .toList();
    final categories = _categoriesFor(styleEntries);
    final requestedCategory = _selectedCategoryByGroup[group] ?? 'all';
    final selectedCategory =
        categories.contains(requestedCategory) ? requestedCategory : 'all';
    final filtered = styleEntries.where((entry) {
      final matchesCategory =
          selectedCategory == 'all' || entry.meta.category == selectedCategory;
      final matchesQuery =
          _query.isEmpty || entry.searchableText.contains(_query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        _FilterRail(
          values: styles,
          selected: selectedStyle,
          labelFor: (value) =>
              value == 'all' ? 'Все стили' : stickerStyleLabel(value),
          onSelected: (value) {
            setState(() {
              _selectedStyleByGroup[group] = value;
              _selectedCategoryByGroup[group] = 'all';
            });
          },
        ),
        const SizedBox(height: 8),
        _FilterRail(
          values: categories,
          selected: selectedCategory,
          labelFor: (value) =>
              value == 'all' ? 'Все темы' : stickerCategoryLabel(value),
          onSelected: (value) {
            setState(() => _selectedCategoryByGroup[group] = value);
          },
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const _StickerSearchEmptyState()
              : GridView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridColumnsFor(context),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _StickerTile(
                      entry: filtered[index],
                      onTap: () =>
                          widget.onStickerSelected(filtered[index].item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StickerSheetHeader extends StatelessWidget {
  const _StickerSheetHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_motion_outlined),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Стикеры',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              '$count',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final List<String> values;
  final String selected;
  final String Function(String value) labelFor;
  final void Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = values[index];
          return FilterChip(
            label: Text(labelFor(value), maxLines: 1),
            selected: selected == value,
            onSelected: (_) => onSelected(value),
          );
        },
      ),
    );
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({
    required this.entry,
    required this.onTap,
  });

  final StickerCatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Image.network(
            entry.assetUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.broken_image_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StickerEmptyState extends StatelessWidget {
  const _StickerEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Стикеры еще не загружены',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _StickerSearchEmptyState extends StatelessWidget {
  const _StickerSearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Ничего не найдено',
        textAlign: TextAlign.center,
      ),
    );
  }
}

List<String> _groupsFor(List<StickerCatalogEntry> entries) {
  final groups = entries.map((entry) => entry.meta.group).toSet().toList();
  groups.sort((left, right) => _rankCompare(stickerGroupOrder, left, right));
  return groups;
}

List<String> _stylesFor(List<StickerCatalogEntry> entries) {
  final styles = entries.map((entry) => entry.meta.style).toSet().toList();
  styles.sort((left, right) => _rankCompare(stickerStyleOrder, left, right));
  return ['all', ...styles];
}

List<String> _categoriesFor(List<StickerCatalogEntry> entries) {
  final categories =
      entries.map((entry) => entry.meta.category).toSet().toList()..sort();
  return ['all', ...categories];
}

int _groupCount(List<StickerCatalogEntry> entries, String group) {
  return entries.where((entry) => entry.meta.group == group).length;
}

int _gridColumnsFor(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width >= 720) return 7;
  if (width >= 560) return 6;
  if (width >= 420) return 5;
  return 4;
}

int _rankCompare(List<String> order, String left, String right) {
  final leftIndex = order.indexOf(left);
  final rightIndex = order.indexOf(right);
  final normalizedLeft = leftIndex < 0 ? order.length : leftIndex;
  final normalizedRight = rightIndex < 0 ? order.length : rightIndex;
  if (normalizedLeft != normalizedRight) {
    return normalizedLeft.compareTo(normalizedRight);
  }
  return left.compareTo(right);
}
