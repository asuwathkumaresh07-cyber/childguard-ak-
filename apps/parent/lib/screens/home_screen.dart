import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'block_list_screen.dart';
import 'blocked_apps_screen.dart';
import 'child_detail_screen.dart';
import 'child_tasks_screen.dart';
import 'parent_alerts_screen.dart';
import '../services/parent_push_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/user_error.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _family = FamilyService();
  final _auth = AuthService();

  Profile? _profile;
  Family? _familyModel;
  List<FamilyMember> _children = [];
  List<AppUsageLog> _activityLogs = [];
  bool _loading = true;
  bool _refreshInProgress = false;
  bool _pushRegistrationAttempted = false;
  int _newAlertCount = 0;
  String? _error;
  Timer? _poll;
  RealtimeChannel? _tamperRealtimeSub;
  RealtimeChannel? _zoneRealtimeSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(
        const Duration(seconds: 30), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tamperRealtimeSub?.unsubscribe();
    _zoneRealtimeSub?.unsubscribe();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _family.reload();
      await _auth.ensureProfile();
      final profile = await _family.fetchMyProfile();
      if (profile != null && !profile.isParent) {
        reportAppError(
          'authorize parent dashboard',
          StateError('A child profile opened the parent app.'),
        );
        setState(() {
          _error = userFacingError;
          _loading = false;
        });
        return;
      }
      final family = await _family.fetchMyFamily();
      final kids = family == null
          ? <FamilyMember>[]
          : await _family.fetchChildren(family.id);
      var activityLogs = <AppUsageLog>[];
      if (family != null && _family.isUsingSupabase && kids.isNotEmpty) {
        try {
          final familyId = family.id;
          final childLogs = await Future.wait(
            kids.map(
              (child) => _family.fetchAppUsageLogs(
                familyId: familyId,
                childId: child.profileId,
                limit: 300,
              ),
            ),
          );
          activityLogs = childLogs.expand((logs) => logs).toList();
        } catch (error) {
          reportAppError('load family activity chart', error);
        }
      }
      if (!mounted) return;
      final familyChanged = _familyModel?.id != family?.id;
      setState(() {
        _profile = profile;
        _familyModel = family;
        _children = kids;
        _activityLogs = activityLogs;
        _loading = false;
      });
      if (familyChanged && family != null) {
        _subscribeToTamperEvents(family.id);
        _subscribeToZoneEvents(family.id);
      }
      if (profile?.isParent == true &&
          _family.isUsingSupabase &&
          ParentPushService.isInitialized &&
          !_pushRegistrationAttempted) {
        _pushRegistrationAttempted = true;
        unawaited(_registerParentPushNotifications());
      }
    } catch (e) {
      if (!mounted) return;
      reportAppError('refresh family dashboard', e);
      setState(() {
        _error = userFacingError;
        _loading = false;
      });
    } finally {
      _refreshInProgress = false;
    }
  }

  void _subscribeToTamperEvents(String familyId) {
    _tamperRealtimeSub?.unsubscribe();
    _tamperRealtimeSub = _family.subscribeToChildTamperEvents(
      familyId,
      (event) {
        if (!mounted) return;
        setState(() => _newAlertCount++);
        final childMember = _children
            .where((member) => member.profileId == event.childId)
            .firstOrNull;
        final name = childMember?.profile?.displayName ?? 'Child';
        showLiveAlertBanner(
          context: context,
          title: 'Protection Tamper Alert',
          message: '$name: ${_tamperEventLabel(event.eventType)}',
          childName: name,
          onView: childMember == null
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChildDetailScreen(
                        familyId: familyId,
                        childId: childMember.profileId,
                        childName: name,
                        initialTab: 1,
                      ),
                    ),
                  );
                },
        );
      },
    );
  }

  void _simulateLiveAlert() {
    final firstKid = _children.firstOrNull;
    final name = firstKid?.profile?.displayName ?? 'Alex';
    showLiveAlertBanner(
      context: context,
      title: 'Active Protection Alert',
      message: '$name: Protection VPN was turned off!',
      childName: name,
      onView: firstKid == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChildDetailScreen(
                    familyId: _familyModel?.id ?? '',
                    childId: firstKid.profileId,
                    childName: name,
                    initialTab: 1,
                  ),
                ),
              );
            },
    );
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

  void _subscribeToZoneEvents(String familyId) {
    _zoneRealtimeSub?.unsubscribe();
    _zoneRealtimeSub = _family.subscribeToZoneEvents(
      familyId,
      (event) {
        if (!mounted) return;
        setState(() => _newAlertCount++);
        final child = _children
            .where((member) => member.profileId == event.childId)
            .firstOrNull;
        final name = child?.profile?.displayName ?? 'Your child';
        final message = switch (event.eventType) {
          'entered' => '$name arrived at a saved place.',
          'exited' => '$name left a saved place.',
          'off_task_app' =>
            '$name opened ${event.packageName ?? 'an app'} in a focus zone.',
          _ => '$name had activity in a saved place.',
        };
        showLiveAlertBanner(
          context: context,
          title: event.eventType == 'off_task_app'
              ? 'Focus Zone Alert'
              : 'Location Alert',
          message: message,
          childName: name,
          onView: child == null
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChildDetailScreen(
                        familyId: familyId,
                        childId: child.profileId,
                        childName: name,
                        initialTab: 4,
                      ),
                    ),
                  );
                },
        );
      },
    );
  }

  Future<void> _registerParentPushNotifications() async {
    if (!ParentPushService.isInitialized) return;
    try {
      final registered = await ParentPushService.registerCurrentParent();
      if (!registered && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Allow Family Guard Parent notifications to receive tamper alerts.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showAppError(context, 'register notifications', e);
    }
  }

  Future<void> _signOut() async {
    try {
      await ParentPushService.unregisterCurrentParent();
      await _auth.signOut();
    } catch (e) {
      if (mounted) showAppError(context, 'sign out', e);
    }
  }

  void _openAlerts() {
    final family = _familyModel;
    if (family == null) return;
    setState(() => _newAlertCount = 0);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParentAlertsScreen(
          familyId: family.id,
          children: List<FamilyMember>.of(_children),
        ),
      ),
    );
  }

  Future<void> _showProfile() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 28,
                child: Icon(Icons.person_outline, size: 30),
              ),
              const SizedBox(height: 10),
              Text(
                _profile?.displayName ?? 'Parent profile',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (_profile?.email.isNotEmpty == true)
                Text(
                  _profile!.email,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () {
                  Navigator.pop(context);
                  _signOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createChildAccount() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      final input = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Create child account'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Child name',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Child email',
                      prefixIcon: Icon(Icons.email),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Temporary password',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (value) {
                      final minLength = _auth.isUsingSupabase ? 6 : 4;
                      if ((value ?? '').length < minLength) {
                        return 'Use at least $minLength characters';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'name': nameController.text.trim().isEmpty
                      ? 'Child'
                      : nameController.text.trim(),
                  'email': emailController.text.trim(),
                  'password': passwordController.text,
                });
              },
              child: const Text('Create account'),
            ),
          ],
        ),
      );
      if (input == null) return;

      final child = await _auth.createChildAccount(
        email: input['email']!,
        password: input['password']!,
        displayName: input['name']!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Child account created for ${child.email}. Share the password securely.'),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppError(context, 'create child account', e);
    } finally {
      nameController.dispose();
      emailController.dispose();
      passwordController.dispose();
    }
  }

  Widget _buildSetupCard() {
    final hasChildren = _children.isNotEmpty;
    final pushConfigured = ParentPushService.isInitialized;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.checklist_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Family setup',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (hasChildren && _family.isUsingSupabase)
                  const Chip(
                    avatar: Icon(Icons.check_circle, size: 16),
                    label: Text('Linked'),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  const Chip(
                    avatar: Icon(Icons.tune, size: 16),
                    label: Text('Setup needed'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Complete these steps to get the most from Family Guard.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            _setupStatusRow(
              icon: hasChildren ? Icons.check_circle : Icons.person_add_alt_1,
              title: hasChildren
                  ? '${_children.length} child account${_children.length == 1 ? '' : 's'} linked'
                  : 'Create your child account',
              subtitle: hasChildren
                  ? 'Open a child profile below to manage protection and activity.'
                  : 'Create it here, then sign in on the child’s device.',
              complete: hasChildren,
              trailing: hasChildren
                  ? null
                  : TextButton(
                      onPressed: _createChildAccount,
                      child: const Text('Create'),
                    ),
            ),
            _setupStatusRow(
              icon: _family.isUsingSupabase
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              title: _family.isUsingSupabase
                  ? 'Cloud sync is configured'
                  : 'Using this device only',
              subtitle: _family.isUsingSupabase
                  ? 'Family settings and activity use Supabase when the device is online.'
                  : 'Sign in with a configured Supabase project to sync across devices.',
              complete: _family.isUsingSupabase,
            ),
            _setupStatusRow(
              icon: pushConfigured
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_outlined,
              title: pushConfigured
                  ? 'Firebase notifications are configured in the app'
                  : 'Closed-app push alerts need setup',
              subtitle: pushConfigured
                  ? 'Server-side FCM credentials are also required for delivery.'
                  : 'In-app alerts work while Parent is open; Firebase is needed for push.',
              complete: pushConfigured,
            ),
            const Divider(height: 18),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.phone_android_rounded),
              title: Text('Finish device setup in each child profile'),
              subtitle: Text(
                'App limits need Usage access and Accessibility. Location is child opt-in and needs background location permission.',
              ),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupStatusRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool complete,
    Widget? trailing,
  }) {
    final color = complete
        ? const Color(0xFF28775F)
        : Theme.of(context).colorScheme.primary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: trailing,
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Family Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Test Live Alert Animation',
            onPressed: _simulateLiveAlert,
            icon: const Icon(Icons.add_alert_rounded, color: Colors.amber),
          ),
          IconButton(
            tooltip: 'Alerts',
            onPressed: _familyModel == null ? null : _openAlerts,
            icon: Badge(
              isLabelVisible: _newAlertCount > 0,
              label: Text(
                _newAlertCount > 99 ? '99+' : '$_newAlertCount',
              ),
              child: _newAlertCount > 0
                  ? const AnimatedAlertTriangle(size: 22, showPulseRings: false)
                  : const Icon(Icons.notifications_none_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: _showProfile,
            icon: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.person_outline, size: 19),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createChildAccount,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Create child'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        const Text(userFacingError,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : AmbientBackground(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        GlassCard(
                          child: Row(
                            children: [
                              GuardianCharacter(
                                size: 66,
                                mood: _newAlertCount > 0 ? GuardianMood.alert : GuardianMood.safe,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hi, ${_profile?.displayName ?? "Parent"}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_familyModel?.name ?? 'My Family'} · ${_children.length} protected child${_children.length == 1 ? '' : 'ren'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF597277),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                ),
                                onPressed: _simulateLiveAlert,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bolt, size: 16, color: Colors.amber),
                                    SizedBox(width: 2),
                                    Text('Test Alert', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        GlassCard(
                          child: DualUsageChart(
                            logs: _activityLogs,
                            title: 'Family Screen Time Analytics',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildSetupCard(),
                        const SizedBox(height: 16),
                        _buildFeaturesSuiteCard(),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Protected Child Devices (${_children.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              onPressed: _createChildAccount,
                              label: const Text('Add Child'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_children.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Icon(Icons.phone_android,
                                      size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No child accounts linked yet.',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Create your child’s account here. It will connect to your Family Guard shield automatically.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 13, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._children.map((m) {
                            final name = m.profile?.displayName.isNotEmpty ==
                                    true
                                ? m.profile!.displayName
                                : 'Child Device (${m.profileId.substring(0, 6)})';
                            return _buildChildOverviewCard(m, name);
                          }),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildFeaturesSuiteCard() {
    final familyId = _familyModel?.id ?? '';
    final firstKid = _children.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Family Guard Features Suite',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_newAlertCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      '$_newAlertCount Alert${_newAlertCount > 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: Column(
            children: [
              // 1. Web Shield
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE0F2F1),
                  child: Icon(Icons.security, color: Colors.teal.shade800),
                ),
                title: const Text('Web Shield & Category Filters', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Block adult sites, malicious domains & 9 categories'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (familyId.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BlockListScreen(familyId: familyId),
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 1),

              // 2. App Guard & Limits
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE8EAF6),
                  child: Icon(Icons.apps_rounded, color: Colors.indigo.shade700),
                ),
                title: const Text('App Guard & Time Limits', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Lock distracting games & set daily minute limits'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (familyId.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BlockedAppsScreen(familyId: familyId),
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 1),

              // 3. Live Tamper & Security Alerts (Moving Red Triangle Notification)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFFEBEE),
                  child: Icon(Icons.warning_rounded, color: Colors.red.shade700),
                ),
                title: Row(
                  children: [
                    const Text('Live Security & Tamper Alerts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    if (_newAlertCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_newAlertCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: const Text('Real-time alerts with animated moving red triangle'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ParentAlertsScreen(
                        familyId: familyId,
                        children: _children,
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1),

              // 4. Tasks, Homework & Rewards
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF3E5F5),
                  child: Icon(Icons.checklist_rounded, color: Colors.purple.shade700),
                ),
                title: const Text('Tasks, Chores & Homework', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Photo proof verification, streaks & screen time credits'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (firstKid != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildTasksScreen(
                          familyId: familyId,
                          childId: firstKid.profileId,
                          childName: firstKid.profile?.displayName ?? 'Child',
                        ),
                      ),
                    );
                  } else {
                    _showNoChildSnack();
                  }
                },
              ),
              const Divider(height: 1),

              // 5. GPS Sentinel & Safe Zones
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE0F7FA),
                  child: Icon(Icons.radar_rounded, color: Colors.cyan.shade800),
                ),
                title: const Text('GPS Sentinel & Safe Zones', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Interactive OpenStreetMap tracking & geofence perimeter alerts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (firstKid != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildDetailScreen(
                          familyId: familyId,
                          childId: firstKid.profileId,
                          childName: firstKid.profile?.displayName ?? 'Child',
                          initialTab: 4, // Tab 4 is Location & Zones
                        ),
                      ),
                    );
                  } else {
                    _showNoChildSnack();
                  }
                },
              ),
              const Divider(height: 1),

              // 6. Categorized Logs (Live stream + Daily/Hourly/Monthly)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFFF3E0),
                  child: Icon(Icons.history_rounded, color: Colors.orange.shade800),
                ),
                title: const Text('Categorized Activity Logs', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Live event stream + Daily, Hourly, and Monthly usage breakdown'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (firstKid != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildDetailScreen(
                          familyId: familyId,
                          childId: firstKid.profileId,
                          childName: firstKid.profile?.displayName ?? 'Child',
                          initialTab: 1, // Tab 1 is Categorized Logs
                        ),
                      ),
                    );
                  } else {
                    _showNoChildSnack();
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChildOverviewCard(FamilyMember member, String name) {
    final familyId = _familyModel?.id ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFE0F2F1),
                  child: Icon(Icons.child_care_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Device Protected', style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildDetailScreen(
                          familyId: familyId,
                          childId: member.profileId,
                          childName: name,
                        ),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Open', style: TextStyle(fontSize: 12)),
                      Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Quick feature shortcut pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildShortcutChip(
                    icon: Icons.bar_chart_rounded,
                    label: 'Graphs',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildDetailScreen(
                          familyId: familyId,
                          childId: member.profileId,
                          childName: name,
                          initialTab: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildShortcutChip(
                    icon: Icons.history_rounded,
                    label: 'Categorized Logs',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildDetailScreen(
                          familyId: familyId,
                          childId: member.profileId,
                          childName: name,
                          initialTab: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildShortcutChip(
                    icon: Icons.public,
                    label: 'Web Shield',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildDetailScreen(
                          familyId: familyId,
                          childId: member.profileId,
                          childName: name,
                          initialTab: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildShortcutChip(
                    icon: Icons.apps,
                    label: 'Limits',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildDetailScreen(
                          familyId: familyId,
                          childId: member.profileId,
                          childName: name,
                          initialTab: 3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildShortcutChip(
                    icon: Icons.radar_rounded,
                    label: 'Radar Map',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChildDetailScreen(
                          familyId: familyId,
                          childId: member.profileId,
                          childName: name,
                          initialTab: 4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  void _showNoChildSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please add a child account first.')),
    );
  }

  Widget _buildDrawer() {
    final familyId = _familyModel?.id;
    return Drawer(
      backgroundColor: const Color(0xFFF1F6F8),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 20),
              child: Row(
                children: [
                  Icon(Icons.shield_moon_outlined,
                      color: Color(0xFF286F69), size: 30),
                  SizedBox(width: 10),
                  Text(
                    'Family Guard',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            _drawerItem(
              icon: Icons.space_dashboard_outlined,
              label: 'Dashboard',
              onTap: () => Navigator.pop(context),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 22, 14, 8),
              child: Text(
                'MONITORING',
                style: TextStyle(
                  color: Color(0xFF6A8387),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            if (_children.isEmpty)
              const ListTile(
                leading: Icon(Icons.child_care_outlined),
                title: Text('No child profiles yet'),
                dense: true,
              )
            else
              ..._children.map((child) {
                final name = child.profile?.displayName.isNotEmpty == true
                    ? child.profile!.displayName
                    : 'Child';
                return _drawerItem(
                  icon: Icons.location_on_outlined,
                  label: '$name · live activity',
                  onTap: () {
                    Navigator.pop(context);
                    if (familyId != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChildDetailScreen(
                            familyId: familyId,
                            childId: child.profileId,
                            childName: name,
                            initialTab: 3,
                          ),
                        ),
                      );
                    }
                  },
                );
              }),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 22, 14, 8),
              child: Text(
                'PROTECTION',
                style: TextStyle(
                  color: Color(0xFF6A8387),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            _drawerItem(
              icon: Icons.public,
              label: 'Blocked websites',
              onTap: () {
                Navigator.pop(context);
                if (familyId != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BlockListScreen(familyId: familyId),
                    ),
                  );
                }
              },
            ),
            _drawerItem(
              icon: Icons.block_outlined,
              label: 'Blocked apps',
              onTap: () {
                Navigator.pop(context);
                if (familyId != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BlockedAppsScreen(familyId: familyId),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: const Color(0xFF3D7978)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      ),
    );
  }
}
