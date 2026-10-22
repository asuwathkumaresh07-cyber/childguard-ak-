import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

import 'child_tasks_screen.dart';
import 'child_plans_screen.dart';
import '../widgets/glass_card.dart';
import '../widgets/user_error.dart';

class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({
    super.key,
    required this.familyId,
    required this.childId,
    required this.childName,
    this.initialTab = 0,
  });

  final String familyId;
  final String childId;
  final String childName;
  final int initialTab;

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen>
    with SingleTickerProviderStateMixin {
  final _family = FamilyService();
  late final TabController _tabs;
  late final DateFormat _fmt = DateFormat('MMM d, h:mm a');

  List<DomainLog> _domains = [];
  List<AppUsageLog> _apps = [];
  List<AppTimeLimit> _timeLimits = [];
  List<ExtraTimeRequest> _extraTimeRequests = [];
  List<VpnControlRequest> _vpnRequests = [];
  List<ChildTamperEvent> _tamperEvents = [];
  ChildDeviceStatus? _deviceStatus;
  String _protectionMode = 'strict';
  Set<String> _currentlyBlockedDomains = {};
  Set<String> _currentlyBlockedApps = {};

  bool _loading = true;
  String? _loadError;
  String _domainFilter = 'all'; // 'all', 'allowed', 'blocked'
  String _searchQuery = '';
  Timer? _poll;
  RealtimeChannel? _realtimeSub;
  RealtimeChannel? _tamperRealtimeSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 5,
      initialIndex: widget.initialTab.clamp(0, 4).toInt(),
      vsync: this,
    );
    _load();
    _poll =
        Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    _realtimeSub = _family.subscribeToDomainLogs(widget.familyId, (newLog) {
      if (!mounted) return;
      if (newLog.childId == widget.childId) {
        setState(() {
          _domains.insert(0, newLog);
        });
      }
    });
    _tamperRealtimeSub = _family.subscribeToChildTamperEvents(
      widget.familyId,
      _onTamperEvent,
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _realtimeSub?.unsubscribe();
    _tamperRealtimeSub?.unsubscribe();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      await _family.reload();
      final domains = await _family.fetchDomainLogs(
        familyId: widget.familyId,
        childId: widget.childId,
        limit: null,
      );
      final apps = await _family.fetchAppUsageLogs(
        familyId: widget.familyId,
        childId: widget.childId,
        limit: null,
      );
      final limits = _family.isUsingSupabase
          ? await _family.fetchAppTimeLimits(
              familyId: widget.familyId,
              childId: widget.childId,
            )
          : <AppTimeLimit>[];
      final extraRequests = _family.isUsingSupabase
          ? await _family.fetchExtraTimeRequests(
              familyId: widget.familyId,
              childId: widget.childId,
            )
          : <ExtraTimeRequest>[];
      final vpnRequests = _family.isUsingSupabase
          ? await _family.fetchVpnControlRequests(
              familyId: widget.familyId,
              childId: widget.childId,
            )
          : <VpnControlRequest>[];
      final protectionMode = _family.isUsingSupabase
          ? await _family.fetchChildProtectionMode(
              familyId: widget.familyId,
              childId: widget.childId,
            )
          : 'strict';
      final deviceStatus = _family.isUsingSupabase
          ? await _family.fetchChildDeviceStatus(widget.childId)
          : null;
      final tamperEvents = _family.isUsingSupabase
          ? await _family.fetchChildTamperEvents(
              familyId: widget.familyId,
              childId: widget.childId,
            )
          : <ChildTamperEvent>[];
      final customBlocks = await _family.fetchBlockDomains(widget.familyId);
      final blockedApps =
          await _family.fetchBlockedAppPackages(widget.familyId);

      if (!mounted) return;
      final knownPendingIds = {
        ..._extraTimeRequests
            .where((request) => request.status == 'pending')
            .map((request) => request.id),
      };
      final newPendingCount = extraRequests
          .where((request) =>
              request.status == 'pending' &&
              !knownPendingIds.contains(request.id))
          .length;
      setState(() {
        _domains = domains;
        _apps = apps;
        _timeLimits = limits;
        _extraTimeRequests = extraRequests;
        _vpnRequests = vpnRequests;
        _deviceStatus = deviceStatus;
        _tamperEvents = tamperEvents;
        _protectionMode = protectionMode;
        _currentlyBlockedDomains =
            customBlocks.map((d) => d.toLowerCase()).toSet();
        _currentlyBlockedApps = blockedApps.toSet();
        _loading = false;
        _loadError = null;
      });
      if (silent && newPendingCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$newPendingCount new request${newPendingCount == 1 ? '' : 's'} from ${widget.childName}.',
            ),
            action: SnackBarAction(
              label: 'Review',
              onPressed: () => _tabs.animateTo(2),
            ),
          ),
        );
      }
    } catch (e) {
      reportAppError('load child activity', e);
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = userFacingError;
        });
      }
    }
  }

  void _onTamperEvent(ChildTamperEvent event) {
    if (!mounted || event.childId != widget.childId) return;
    setState(() {
      if (_tamperEvents.every((existing) => existing.id != event.id)) {
        _tamperEvents.insert(0, event);
      }
    });
    showLiveAlertBanner(
      context: context,
      title: 'Security Alert Triggered',
      message: '${widget.childName}: ${_tamperEventLabel(event.eventType)}',
      childName: widget.childName,
      onView: () {
        _tabs.animateTo(1);
      },
    );
    _load(silent: true);
  }

  String _tamperEventLabel(String eventType) {
    return switch (eventType) {
      'vpn_disabled' => 'protection VPN turned off.',
      'vpn_enabled' => 'protection VPN turned back on.',
      'usage_access_revoked' => 'Usage access was turned off.',
      'usage_access_restored' => 'Usage access was restored.',
      'accessibility_disabled' => 'App Blocker monitoring was turned off.',
      'accessibility_restored' => 'App Blocker monitoring was restored.',
      'location_sharing_disabled' => 'Location sharing was turned off.',
      'location_sharing_enabled' => 'Location sharing was turned on.',
      _ => 'a protection setting changed.',
    };
  }

  Future<void> _blockDomain(String rawDomain) async {
    final domain = rawDomain.trim().toLowerCase();
    try {
      await _family.addBlockDomain(widget.familyId, domain);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blocked $domain across child devices'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      await _load(silent: true);
    } catch (e) {
      if (mounted) showAppError(context, 'block website', e);
    }
  }

  Future<void> _unblockDomain(String domain) async {
    try {
      final entries = await _family.fetchBlockList(widget.familyId);
      final match = entries
          .where((e) => e.domain.toLowerCase() == domain.toLowerCase())
          .firstOrNull;

      if (match != null && match.id.isNotEmpty) {
        await _family.removeBlockDomain(match.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unblocked $domain')),
          );
        }
        await _load(silent: true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$domain is managed by a blocked category')),
          );
        }
      }
    } catch (e) {
      if (mounted) showAppError(context, 'unblock website', e);
    }
  }

  Future<void> _blockApp(String packageName, String label) async {
    try {
      await _family.addBlockedApp(
        familyId: widget.familyId,
        packageName: packageName,
        appLabel: label,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blocked $label'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      await _load(silent: true);
    } catch (e) {
      if (mounted) showAppError(context, 'block app', e);
    }
  }

  List<DomainLog> get _filteredDomains {
    return _domains.where((d) {
      if (_domainFilter == 'allowed' && d.isBlocked) return false;
      if (_domainFilter == 'blocked' && !d.isBlocked) return false;
      if (_searchQuery.isNotEmpty &&
          !d.domain.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} — Activity Monitor'),
        actions: [
          IconButton(
            tooltip: 'Child tasks',
            icon: const Icon(Icons.checklist_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChildTasksScreen(
                    familyId: widget.familyId,
                    childId: widget.childId,
                    childName: widget.childName,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Usage & Graphs'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Categorized Logs'),
            Tab(icon: Icon(Icons.public), text: 'Web Shield'),
            Tab(icon: Icon(Icons.apps), text: 'Apps & Limits'),
            Tab(icon: Icon(Icons.radar), text: 'Location & Zones'),
          ],
        ),
      ),
      body: AmbientBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_loadError != null)
                    MaterialBanner(
                      content: Text(_loadError!),
                      leading: const Icon(Icons.cloud_off),
                      actions: [
                        TextButton(
                          onPressed: () => _load(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  _buildProtectionStatusBanner(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _buildUsageAndGraphsTab(),
                        _buildCategorizedLogsTab(),
                        _buildNetworkTab(),
                        _buildControlsTab(),
                        ChildPlansScreen(
                          familyId: widget.familyId,
                          childId: widget.childId,
                          childName: widget.childName,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildNetworkTab() {
    final filtered = _filteredDomains;

    return Column(
      children: [
        // Filter chips and search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search domain activities...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Filter: ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _domainFilter == 'all',
                    onSelected: (_) => setState(() => _domainFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Allowed'),
                    selected: _domainFilter == 'allowed',
                    selectedColor: Colors.green.shade100,
                    onSelected: (_) =>
                        setState(() => _domainFilter = 'allowed'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Blocked'),
                    selected: _domainFilter == 'blocked',
                    selectedColor: Colors.red.shade100,
                    onSelected: (_) =>
                        setState(() => _domainFilter = 'blocked'),
                  ),
                ],
              ),
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
                      Icon(Icons.public, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        _domains.isEmpty
                            ? 'No network traffic recorded yet.\nTurn Protection ON in the Child app.'
                            : 'No domains match this filter.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final d = filtered[i];
                      final isAlreadyBlocked = _currentlyBlockedDomains
                              .contains(d.domain.toLowerCase()) ||
                          d.isBlocked;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: d.isBlocked
                              ? Colors.red.shade100
                              : Colors.green.shade100,
                          child: Icon(
                            d.isBlocked
                                ? Icons.block
                                : Icons.check_circle_outline,
                            color: d.isBlocked
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          d.domain,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(_fmt.format(d.occurredAt.toLocal())),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: d.isBlocked
                                    ? Colors.red.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: d.isBlocked
                                      ? Colors.red.shade300
                                      : Colors.green.shade300,
                                ),
                              ),
                              child: Text(
                                d.action.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: d.isBlocked
                                      ? Colors.red.shade800
                                      : Colors.green.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Quick Action: Block / Unblock domain
                            if (!isAlreadyBlocked)
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red.shade100,
                                  foregroundColor: Colors.red.shade900,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                ),
                                onPressed: () => _blockDomain(d.domain),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shield, size: 14),
                                    SizedBox(width: 4),
                                    Text('Block',
                                        style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              )
                            else
                              IconButton(
                                tooltip: 'Unblock domain',
                                icon: const Icon(Icons.lock_open, size: 18),
                                onPressed: () => _unblockDomain(d.domain),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildUsageAndGraphsTab() {
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: _apps.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassCard(
                  child: DualUsageChart(
                    logs: _apps,
                    title: '${widget.childName}’s Usage Analytics',
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Recorded App Sessions (${_apps.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 6),
                if (_apps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No app sessions recorded yet for today.'),
                    ),
                  ),
              ],
            );
          }

          final a = _apps[i - 1];
          final isBlocked = _currentlyBlockedApps.contains(a.packageName);
          final dur = _formatDuration(a.durationSeconds);
          final appName = a.appLabel.isEmpty ? a.packageName : a.appLabel;

          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            tileColor: Colors.white.withValues(alpha: .75),
            leading: CircleAvatar(
              backgroundColor:
                  isBlocked ? Colors.red.shade100 : Colors.blue.shade100,
              child: Icon(
                isBlocked ? Icons.block : Icons.smartphone,
                color: isBlocked ? Colors.red.shade800 : Colors.blue.shade800,
              ),
            ),
            title: Text(
              appName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(_fmt.format(a.startedAt.toLocal())),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dur.isNotEmpty) ...[
                  Text(dur,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                ],
                if (!isBlocked)
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                      foregroundColor: Colors.red.shade900,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _blockApp(a.packageName, appName),
                    child: const Text(
                      'Block',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                else
                  const Chip(
                    label: Text('Blocked', style: TextStyle(fontSize: 11)),
                    backgroundColor: Color(0xFFFFCDD2),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategorizedLogsTab() {
    return CategorizedLogsView(
      appLogs: _apps,
      domainLogs: _domains,
      tamperEvents: _tamperEvents,
      childName: widget.childName,
      onBlockDomain: _blockDomain,
      onBlockApp: _blockApp,
      isDomainBlocked: (d) => _currentlyBlockedDomains.contains(d.toLowerCase()),
      isAppBlocked: (p) => _currentlyBlockedApps.contains(p),
    );
  }

  Future<void> _setAppTimeLimit() async {
    final packageController = TextEditingController();
    final labelController = TextEditingController();
    final minutesController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set daily app limit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'App name'),
            ),
            TextField(
              controller: packageController,
              decoration:
                  const InputDecoration(labelText: 'Android package name'),
            ),
            TextField(
              controller: minutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Daily limit (minutes)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save limit'),
          ),
        ],
      ),
    );

    final packageName = packageController.text.trim();
    final appLabel = labelController.text.trim();
    final minutes = int.tryParse(minutesController.text.trim());
    packageController.dispose();
    labelController.dispose();
    minutesController.dispose();

    if (saved != true) return;
    if (packageName.isEmpty || minutes == null || minutes <= 0) {
      _showMessage(
          'Enter an app package name and a positive limit in minutes.');
      return;
    }

    try {
      await _family.saveAppTimeLimit(
        familyId: widget.familyId,
        childId: widget.childId,
        packageName: packageName,
        appLabel: appLabel.isEmpty ? packageName : appLabel,
        dailyLimitSeconds: minutes * 60,
      );
      await _load(silent: true);
    } catch (e) {
      _showError('save app limit', e);
    }
  }

  Future<void> _removeAppTimeLimit(AppTimeLimit limit) async {
    try {
      await _family.removeAppTimeLimit(
        familyId: widget.familyId,
        id: limit.id,
      );
      await _load(silent: true);
    } catch (e) {
      _showError('remove app limit', e);
    }
  }

  Future<void> _resolveExtraTimeRequest(
    ExtraTimeRequest request, {
    required bool approve,
  }) async {
    try {
      await _family.resolveExtraTimeRequest(
        familyId: widget.familyId,
        id: request.id,
        approve: approve,
        grantedMinutes: approve ? request.requestedMinutes : null,
      );
      await _load(silent: true);
    } catch (e) {
      _showError('resolve extra time request', e);
    }
  }

  Future<void> _generateProtectionCode(String requestedAction) async {
    try {
      final code = await _family.createProtectionControlCode(
        familyId: widget.familyId,
        childId: widget.childId,
        requestedAction: requestedAction,
      );
      if (!mounted) return;
      final actionLabel = requestedAction == 'enable' ? 'turn ON' : 'turn OFF';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Code to $actionLabel protection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                code.code,
                style:
                    Theme.of(dialogContext).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 5,
                        ),
              ),
              const SizedBox(height: 12),
              Text(
                'Give this one-use code to ${widget.childName}. '
                'It expires at ${DateFormat('h:mm a').format(code.expiresAt.toLocal())}.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code.code));
                Navigator.pop(dialogContext);
                _showMessage('Protection code copied.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy code'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('generate protection code', e);
    }
  }

  Future<void> _setProtectionMode(String mode) async {
    try {
      await _family.setChildProtectionMode(
        familyId: widget.familyId,
        childId: widget.childId,
        mode: mode,
      );
      if (!mounted) return;
      setState(() => _protectionMode = mode);
      _showMessage(
        mode == 'strict'
            ? 'Strict mode enabled. Child pause requests are disabled.'
            : 'Friendly mode enabled. Child can request a protection pause.',
      );
    } catch (e) {
      _showError('update protection mode', e);
    }
  }

  Future<String?> _askParentPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm parent password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Parent password'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return password;
  }

  Future<void> _resolveVpnRequest(
    VpnControlRequest request, {
    required bool approve,
  }) async {
    try {
      if (approve) {
        final password = await _askParentPassword();
        if (password == null) return;
        await AuthService().verifyCurrentPassword(password);
      }
      await _family.resolveVpnControlRequest(
        familyId: widget.familyId,
        id: request.id,
        approve: approve,
      );
      await _load(silent: true);
    } catch (e) {
      _showError('resolve protection request', e);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showError(String action, Object error) {
    reportAppError(action, error);
    _showMessage(userFacingError);
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final duration = Duration(seconds: seconds);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '<1m';
  }

  Widget _buildProtectionStatusBanner() {
    final vpnEnabled = _deviceStatus?.vpnEnabled;
    final action = vpnEnabled == true ? 'disable' : 'enable';
    final statusText = vpnEnabled == null
        ? 'Waiting for Child app to report VPN status'
        : vpnEnabled
            ? 'Protection is Active'
            : 'Protection is OFF';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            GuardianCharacter(
              size: 48,
              mood: vpnEnabled == false ? GuardianMood.alert : GuardianMood.safe,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        vpnEnabled == true ? Icons.shield : Icons.shield_outlined,
                        size: 16,
                        color: vpnEnabled == true
                            ? const Color(0xFF2D806D)
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.childName} · ${_protectionMode.toUpperCase()} mode',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => _generateProtectionCode(action),
                  child: Text(vpnEnabled == true ? 'Turn OFF' : 'Turn ON', style: const TextStyle(fontSize: 11)),
                ),
                IconButton(
                  tooltip: 'Simulate Live Alert',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showLiveAlertBanner(
                      context: context,
                      title: 'Live Security Alert',
                      message: '${widget.childName}: Protection VPN turned off unexpectedly!',
                      childName: widget.childName,
                      onView: () => _tabs.animateTo(1),
                    );
                  },
                  icon: const Icon(Icons.bolt, size: 20, color: Colors.amber),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsTab() {
    if (!_family.isUsingSupabase) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            userFacingError,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Protection mode',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _protectionMode == 'strict'
                      ? 'Strict: no child pause requests. Every VPN change still requires a new parent code.'
                      : 'Friendly: the child may request a pause. After approval, send a new parent code to apply it.',
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'strict',
                      label: Text('Strict'),
                      icon: Icon(Icons.lock),
                    ),
                    ButtonSegment(
                      value: 'friendly',
                      label: Text('Friendly'),
                      icon: Icon(Icons.favorite_outline),
                    ),
                  ],
                  selected: {_protectionMode},
                  onSelectionChanged: (selection) =>
                      _setProtectionMode(selection.first),
                ),
              ],
            ),
          ),
        ),
        if (_protectionMode == 'friendly') ...[
          const SizedBox(height: 12),
          const Text(
            'Friendly mode pause requests',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (_vpnRequests
              .where((request) => request.status == 'pending')
              .isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No pending protection pause requests.'),
            )
          else
            ..._vpnRequests.where((request) => request.status == 'pending').map(
                  (request) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text('Child requests Protection OFF'),
                    subtitle: Text(
                      DateFormat('MMM d, h:mm a')
                          .format(request.requestedAt.toLocal()),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Deny request',
                          onPressed: () =>
                              _resolveVpnRequest(request, approve: false),
                          icon: const Icon(Icons.close, color: Colors.red),
                        ),
                        IconButton(
                          tooltip: 'Approve request',
                          onPressed: () =>
                              _resolveVpnRequest(request, approve: true),
                          icon: const Icon(Icons.check, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Protection controls',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Generate a new one-use code for each VPN change. The child enters it in the Child app. Codes expire after 10 minutes.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _generateProtectionCode('enable'),
                      icon: const Icon(Icons.shield),
                      label: const Text('Code to turn ON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _generateProtectionCode('disable'),
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Code to turn OFF'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Child device protection status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_deviceStatus == null)
                  const Text(
                    'Waiting for the Child app to report its protection status.',
                  )
                else ...[
                  Text(
                    'Last connected ${DateFormat('MMM d, h:mm a').format(_deviceStatus!.lastSeenAt.toLocal())}',
                  ),
                  _buildStatusRow('Protection VPN', _deviceStatus!.vpnEnabled),
                  _buildStatusRow(
                    'Usage access',
                    _deviceStatus!.usageAccessEnabled,
                  ),
                  _buildStatusRow(
                    'App Blocker monitoring',
                    _deviceStatus!.accessibilityEnabled,
                  ),
                ],
                const Divider(height: 24),
                const Text(
                  'Recent tamper alerts',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                if (_tamperEvents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No protection changes reported.'),
                  )
                else
                  ..._tamperEvents.take(5).map(
                        (event) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.warning_amber,
                            color: Colors.deepOrange,
                          ),
                          title: Text(_tamperEventLabel(event.eventType)),
                          subtitle: Text(
                            DateFormat('MMM d, h:mm a')
                                .format(event.occurredAt.toLocal()),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Daily app limits',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.icon(
              onPressed: _setAppTimeLimit,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        if (_timeLimits.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No daily app limits configured.'),
          )
        else
          ..._timeLimits.map((limit) {
            final appName =
                limit.appLabel.isEmpty ? limit.packageName : limit.appLabel;
            final minutes = limit.dailyLimitSeconds ~/ 60;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: Text(appName),
              subtitle: Text('$minutes minutes per day · ${limit.packageName}'),
              trailing: IconButton(
                tooltip: 'Remove app limit',
                onPressed: () => _removeAppTimeLimit(limit),
                icon: const Icon(Icons.delete_outline),
              ),
            );
          }),
        const Divider(height: 32),
        const Text(
          'Extra-time requests',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (_extraTimeRequests.where((r) => r.status == 'pending').isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No pending extra-time requests.'),
          )
        else
          ..._extraTimeRequests
              .where((request) => request.status == 'pending')
              .map((request) {
            final appName = request.appLabel.isEmpty
                ? request.packageName
                : request.appLabel;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.more_time),
              title: Text(appName),
              subtitle: Text(
                'Requests ${request.requestedMinutes} minutes'
                '${request.tradeSuggestion == null ? '' : '\n${request.tradeSuggestion}'}',
              ),
              isThreeLine: request.tradeSuggestion != null,
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Deny request',
                    onPressed: () =>
                        _resolveExtraTimeRequest(request, approve: false),
                    icon: const Icon(Icons.close, color: Colors.red),
                  ),
                  IconButton(
                    tooltip: 'Approve request',
                    onPressed: () =>
                        _resolveExtraTimeRequest(request, approve: true),
                    icon: const Icon(Icons.check, color: Colors.green),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStatusRow(String label, bool enabled) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        enabled ? Icons.check_circle : Icons.error,
        color: enabled ? Colors.green : Colors.red,
      ),
      title: Text(label),
      trailing: Text(enabled ? 'ON' : 'OFF'),
    );
  }
}
