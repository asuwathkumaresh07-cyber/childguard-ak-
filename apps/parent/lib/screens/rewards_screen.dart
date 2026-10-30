import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';
import '../widgets/user_error.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen(
      {super.key,
      required this.familyId,
      required this.children,
      this.familyService});
  final String familyId;
  final List<FamilyMember> children;
  final FamilyService? familyService;
  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  late final family = widget.familyService ?? FamilyService();
  late String? childId = widget.children.firstOrNull?.profileId;
  List<ExtraTimeRequest> requests = [];
  List<ChildTask> tasks = [];
  ChildStreak? streak;
  String category = 'Requests';
  bool loading = true;
  bool busy = false;
  String? error;
  int generation = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!busy && !loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    final id = childId;
    final ticket = ++generation;
    if (id == null) {
      setState(() => loading = false);
      return;
    }
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final nextRequests = await family.fetchExtraTimeRequests(
          familyId: widget.familyId, childId: id);
      final nextTasks =
          await family.fetchChildTasks(familyId: widget.familyId, childId: id);
      final nextStreak = await family.fetchChildStreak(id);
      if (mounted && ticket == generation) {
        setState(() {
          requests = nextRequests;
          tasks = nextTasks;
          streak = nextStreak;
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      reportAppError('load rewards', e);
      if (mounted && ticket == generation) {
        setState(() {
          error = userFacingError;
          loading = false;
        });
      }
    }
  }

  Future<void> _review(ExtraTimeRequest request, bool approve) async {
    if (busy) return;
    var input = '${request.requestedMinutes}';
    String? validation;
    final minutes = await showDialog<int>(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (context, refresh) => AlertDialog(
                    title: Text(approve ? 'Approve reward' : 'Decline reward?'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(request.appLabel.isEmpty
                          ? request.packageName
                          : request.appLabel),
                      Text('${request.requestedMinutes} minutes requested'),
                      if (approve)
                        TextFormField(
                            initialValue: input,
                            onChanged: (value) => input = value,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: 'Minutes to grant (1–120)',
                                errorText: validation)),
                      if (approve)
                        const Text(
                            'Extra daily time lasts for today. Access to a blocked app expires after the approved minutes, starting from approval.'),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            final amount = int.tryParse(input.trim());
                            if (approve &&
                                (amount == null ||
                                    amount < 1 ||
                                    amount > 120)) {
                              refresh(
                                  () => validation = 'Enter 1 to 120 minutes.');
                              return;
                            }
                            Navigator.pop(context, approve ? amount : 0);
                          },
                          child: Text(
                              approve ? 'Approve & give reward' : 'Decline'))
                    ])));
    if (minutes == null || !mounted) return;
    setState(() => busy = true);
    try {
      await family.resolveExtraTimeRequest(
          familyId: widget.familyId,
          id: request.id,
          approve: approve,
          grantedMinutes: approve ? minutes : null);
      await _load(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(approve
                ? 'Reward approved. The Child app will apply it on sync.'
                : 'Request declined.')));
      }
    } catch (e) {
      if (mounted) showAppError(context, 'review reward', e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _task(ChildTask task, bool approve) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await family.reviewChildTask(
          familyId: widget.familyId, taskId: task.id, approve: approve);
      await _load(silent: true);
    } catch (e) {
      if (mounted) showAppError(context, 'award task points', e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _photo(ChildTask task) async {
    try {
      final url = await family.createTaskPhotoUrl(task.submissionPhotoPath!);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: Text(task.title),
                  content: Image.network(url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Text('Photo could not load. Please retry.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Close'))
                  ]));
    } catch (e) {
      if (mounted) showAppError(context, 'view task proof', e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rewards & approvals'), actions: [
          IconButton(
              tooltip: 'Refresh rewards',
              onPressed: busy || loading ? null : () => _load(),
              icon: const Icon(Icons.refresh))
        ]),
        body: widget.children.isEmpty
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Add a child account to review rewards.')))
            : RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<String>(
                          key: ValueKey(childId),
                          initialValue: childId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Child'),
                          items: [
                            for (final child in widget.children)
                              DropdownMenuItem(
                                  value: child.profileId,
                                  child: Text(
                                      child.profile?.displayName ?? 'Child',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: busy
                              ? null
                              : (id) {
                                  setState(() {
                                    childId = id;
                                    requests = [];
                                    tasks = [];
                                    streak = null;
                                  });
                                  _load();
                                }),
                      const SizedBox(height: 12),
                      const Text(
                          'Children earn buddy badges and themes themselves. Parents approve extra screen time, temporary app access, and submitted task points.'),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        for (final label in [
                          'Requests',
                          'Tasks & points',
                          'History'
                        ])
                          ChoiceChip(
                              label: Text(label),
                              selected: category == label,
                              onSelected: (_) =>
                                  setState(() => category = label))
                      ]),
                      if (loading)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator())),
                      if (error != null)
                        Card(
                            child: ListTile(
                                title: Text(error!),
                                trailing: TextButton(
                                    onPressed: () => _load(),
                                    child: const Text('Retry')))),
                      if (!loading && error == null) ...[
                        if (category == 'Tasks & points') ...[
                          Card(
                              child: ListTile(
                                  leading: const Icon(Icons.stars_outlined),
                                  title: Text(
                                      '${streak?.totalPoints ?? 0} approved task points'),
                                  subtitle: Text(
                                      '${streak?.currentStreak ?? 0}-day task streak · Time rewards still need approval'))),
                          if (!tasks.any((task) => task.status == 'submitted'))
                            const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                    'No submitted tasks waiting for review.')),
                          for (final task
                              in tasks.where((t) => t.status == 'submitted'))
                            Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(task.title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700)),
                                          Text(
                                              '${task.points} points on approval'),
                                          if (task.submissionPhotoPath != null)
                                            TextButton.icon(
                                                onPressed: () => _photo(task),
                                                icon: const Icon(Icons.photo),
                                                label: const Text(
                                                    'View photo proof')),
                                          Wrap(spacing: 8, children: [
                                            FilledButton(
                                                onPressed: busy
                                                    ? null
                                                    : () => _task(task, true),
                                                child: const Text(
                                                    'Approve & award points')),
                                            TextButton(
                                                onPressed: busy
                                                    ? null
                                                    : () => _task(task, false),
                                                child: const Text('Try again'))
                                          ]),
                                        ]))),
                        ] else ...[
                          if (!requests.any((r) => category == 'Requests'
                              ? r.status == 'pending'
                              : r.status != 'pending'))
                            Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(category == 'Requests'
                                    ? 'No reward requests waiting. Children can request time or app access in Focus.'
                                    : 'No reviewed rewards yet.')),
                          for (final request in requests.where((r) =>
                              category == 'Requests'
                                  ? r.status == 'pending'
                                  : r.status != 'pending'))
                            Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                              request.appLabel.isEmpty
                                                  ? request.packageName
                                                  : request.appLabel,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700)),
                                          Text(
                                              '${request.requestedMinutes} min requested · ${DateFormat('MMM d, h:mm a').format(request.requestedAt.toLocal())}'),
                                          if (request.status == 'pending')
                                            Wrap(spacing: 8, children: [
                                              FilledButton.icon(
                                                  onPressed: busy
                                                      ? null
                                                      : () => _review(
                                                          request, true),
                                                  icon:
                                                      const Icon(Icons.redeem),
                                                  label: const Text('Approve')),
                                              TextButton(
                                                  onPressed: busy
                                                      ? null
                                                      : () => _review(
                                                          request, false),
                                                  child: const Text('Decline')),
                                            ])
                                          else
                                            Text(request.status == 'approved'
                                                ? '${request.grantedMinutes ?? 0} min approved${request.resolvedBy == null ? ' by legacy automatic rules' : ' by parent'}'
                                                : 'Declined'),
                                        ]))),
                        ],
                      ],
                    ])),
      );
}
