import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../widgets/user_error.dart';

class BlockedAppsScreen extends StatefulWidget {
  const BlockedAppsScreen(
      {super.key, required this.familyId, this.familyService});

  final String familyId;
  final FamilyService? familyService;

  @override
  State<BlockedAppsScreen> createState() => _BlockedAppsScreenState();
}

class _BlockedAppsScreenState extends State<BlockedAppsScreen> {
  late final _family = widget.familyService ?? FamilyService();
  final _packageController = TextEditingController();
  final _labelController = TextEditingController();
  List<BlockedAppEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _packageController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await _family.reload();
      final entries = await _family.fetchBlockedApps(widget.familyId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (mounted) showAppError(context, 'load blocked apps', e);
    }
  }

  Future<void> _addCustom() async {
    final pkg = _packageController.text.trim();
    if (pkg.isEmpty) return;
    try {
      await _family.addBlockedApp(
        familyId: widget.familyId,
        packageName: pkg,
        appLabel: _labelController.text.trim(),
      );
      if (!mounted) return;
      _packageController.clear();
      _labelController.clear();
      await _load();
    } catch (e) {
      if (mounted) showAppError(context, 'add blocked app', e);
    }
  }

  Future<void> _togglePreset(Map<String, String> preset, bool enable) async {
    try {
      if (enable) {
        await _family.addBlockedApp(
          familyId: widget.familyId,
          packageName: preset['package']!,
          appLabel: preset['label']!,
        );
      } else {
        final match = _entries.where((e) => e.packageName == preset['package']);
        for (final e in match) {
          await _family.removeBlockedApp(e.id);
        }
      }
      await _load();
    } catch (e) {
      if (mounted) showAppError(context, 'update blocked app', e);
    }
  }

  Future<void> _remove(BlockedAppEntry entry) async {
    try {
      await _family.removeBlockedApp(entry.id);
      await _load();
    } catch (e) {
      if (mounted) showAppError(context, 'remove blocked app', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockedPkgs = _entries.map((e) => e.packageName).toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked apps')),
      body: _loading
          ? const AppLoadingView(
              message: 'Loading app controls', icon: Icons.apps_rounded)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GlassCard(
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC3545).withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const LiveIcon(
                          Icons.shield_outlined,
                          color: Color(0xFFDC3545),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_entries.length} apps blocked',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const Text('Manage app access for your family'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Presets',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...CommonBlockedApps.presets.map((preset) {
                  final on = blockedPkgs.contains(preset['package']);
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(preset['label']!),
                    subtitle: const Text('Block on child devices'),
                    value: on,
                    onChanged: (v) => _togglePreset(preset, v),
                  );
                }),
                const Divider(height: 32),
                Text(
                  'Custom package',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'App label (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _packageController,
                  decoration: const InputDecoration(
                    labelText: 'Package name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                    onPressed: _addCustom, child: const Text('Add app')),
                const Divider(height: 32),
                Text(
                  'Currently blocked (${_entries.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_entries.isEmpty)
                  const Text('No apps blocked yet')
                else
                  ..._entries.map(
                    (e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title:
                          Text(e.appLabel.isEmpty ? e.packageName : e.appLabel),
                      trailing: IconButton(
                        icon: const LiveIcon(Icons.delete_outline),
                        onPressed: () => _remove(e),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
