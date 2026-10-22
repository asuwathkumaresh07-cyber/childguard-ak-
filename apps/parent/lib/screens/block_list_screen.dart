import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../widgets/glass_card.dart';
import '../widgets/user_error.dart';

class BlockListScreen extends StatefulWidget {
  const BlockListScreen({super.key, required this.familyId});

  final String familyId;

  @override
  State<BlockListScreen> createState() => _BlockListScreenState();
}

class _BlockListScreenState extends State<BlockListScreen>
    with SingleTickerProviderStateMixin {
  final _family = FamilyService();
  final _domainController = TextEditingController();
  late final TabController _tabs;

  List<BlockListEntry> _entries = [];
  Set<String> _categories = {};
  bool _loading = true;
  String _domainSearch = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _domainController.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _family.reload();
      final entries = await _family.fetchBlockList(widget.familyId);
      final cats = await _family.fetchBlockedCategories(widget.familyId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _categories = cats.toSet();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppError(context, 'load website filters', e);
    }
  }

  Future<void> _toggleCategory(BlockCategory cat, bool enabled) async {
    try {
      await _family.toggleCategory(cat, enabled, familyId: widget.familyId);
      await _load();
    } catch (e) {
      if (mounted) showAppError(context, 'update website category', e);
    }
  }

  Future<void> _add() async {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) return;
    try {
      await _family.addBlockDomain(widget.familyId, domain);
      _domainController.clear();
      await _load();
    } catch (e) {
      if (mounted) showAppError(context, 'add blocked domain', e);
    }
  }

  Future<void> _remove(BlockListEntry entry) async {
    try {
      await _family.removeBlockDomain(entry.id);
      await _load();
    } catch (e) {
      if (mounted) showAppError(context, 'remove blocked domain', e);
    }
  }

  IconData _iconForCategory(BlockCategory cat) {
    switch (cat) {
      case BlockCategory.adult:
        return Icons.explicit;
      case BlockCategory.social:
        return Icons.people;
      case BlockCategory.gambling:
        return Icons.casino;
      case BlockCategory.games:
        return Icons.sports_esports;
      case BlockCategory.streaming:
        return Icons.play_circle;
      case BlockCategory.violence:
        return Icons.warning;
    }
  }

  int get _totalBlockedCount {
    final activeCategories =
        _categories.map(BlockCategoryX.fromId).whereType<BlockCategory>();
    final fromCategories = CategoryDomainLists.domainsFor(activeCategories);
    final customDomains = _entries.map((e) => e.domain.toLowerCase()).toSet();
    return {...fromCategories, ...customDomains}.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Website Filtering'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Categories (${_categories.length})'),
            Tab(text: 'Custom Domains (${_entries.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildCategoriesTab(),
                _buildDomainsTab(),
              ],
            ),
    );
  }

  Widget _buildCategoriesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  color: Color(0xFF347A75), size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_totalBlockedCount sites filtered',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Choose categories or add a domain to protect your family.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...BlockCategory.values.map((cat) {
          final on = _categories.contains(cat.id);
          final count = CategoryDomainLists.domains[cat]?.length ?? 0;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: SwitchListTile(
              secondary: CircleAvatar(
                backgroundColor:
                    on ? Colors.red.shade100 : Colors.grey.shade200,
                child: Icon(
                  _iconForCategory(cat),
                  color: on ? Colors.red.shade800 : Colors.grey.shade600,
                ),
              ),
              title: Text(
                cat.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                  '${cat.description}\nIncludes ~$count top curated sites'),
              isThreeLine: true,
              value: on,
              onChanged: (v) => _toggleCategory(cat, v),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDomainsTab() {
    final filtered = _entries.where((e) {
      if (_domainSearch.isNotEmpty &&
          !e.domain.toLowerCase().contains(_domainSearch.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _domainController,
                      decoration: const InputDecoration(
                        labelText: 'Specific domain to block',
                        hintText: 'e.g. reddit.com or badsite.org',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.language),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Block'),
                  ),
                ],
              ),
              if (_entries.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search blocked domains...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _domainSearch = v.trim()),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        _entries.isEmpty
                            ? 'No custom blocked domains.\nEnter a domain above to block it.'
                            : 'No domains match your search.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = filtered[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFEBEE),
                        child: Icon(Icons.block, color: Colors.red),
                      ),
                      title: Text(
                        e.domain,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Added on ${e.createdAt.toLocal().toString().split('.').first}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        tooltip: 'Unblock domain',
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _remove(e),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
