import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

import '../widgets/glass_card.dart';
import '../widgets/user_error.dart';

class ChildTasksScreen extends StatefulWidget {
  const ChildTasksScreen({
    super.key,
    required this.familyId,
    required this.childId,
    required this.childName,
  });

  final String familyId;
  final String childId;
  final String childName;

  @override
  State<ChildTasksScreen> createState() => _ChildTasksScreenState();
}

class _ChildTasksScreenState extends State<ChildTasksScreen> {
  final _family = FamilyService();
  bool _loading = true;
  String? _error;
  List<ChildTask> _tasks = [];
  String _taskFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await _family.fetchChildTasks(
        familyId: widget.familyId,
        childId: widget.childId,
      );
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (error) {
      reportAppError('load child tasks', error);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingError;
      });
    }
  }

  Future<void> _createTask() async {
    final title = TextEditingController();
    final description = TextEditingController();
    final points = TextEditingController(text: '10');
    var taskType = 'task';
    DateTime? dueAt;
    try {
      final values = await showDialog<(String, String, int, String, DateTime?)>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Assign work to ${widget.childName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: taskType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'task', child: Text('Task')),
                      DropdownMenuItem(
                        value: 'homework',
                        child: Text('Homework'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => taskType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: taskType == 'homework' ? 'Homework' : 'Task',
                      hintText: taskType == 'homework'
                          ? 'e.g. Science chapter 4'
                          : 'e.g. Tidy your desk',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Instructions (optional)',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: dueAt ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (selected != null) {
                        setDialogState(() => dueAt = selected);
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      dueAt == null
                          ? 'Add a due date'
                          : 'Due ${DateFormat('MMM d, y').format(dueAt!)}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: points,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Reward points'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final reward = int.tryParse(points.text);
                  if (title.text.trim().isEmpty ||
                      reward == null ||
                      reward < 0 ||
                      reward > 1000) {
                    return;
                  }
                  Navigator.pop(
                    context,
                    (
                      title.text.trim(),
                      description.text.trim(),
                      reward,
                      taskType,
                      dueAt,
                    ),
                  );
                },
                child: const Text('Assign'),
              ),
            ],
          ),
        ),
      );
      if (values == null) return;
      await _family.createChildTask(
        familyId: widget.familyId,
        childId: widget.childId,
        title: values.$1,
        description: values.$2,
        taskType: values.$4,
        dueAt: values.$5,
        points: values.$3,
      );
      await _load();
    } catch (error) {
      _showError('assign child task', error);
    } finally {
      title.dispose();
      description.dispose();
      points.dispose();
    }
  }

  Future<void> _reviewTask(ChildTask task, {required bool approve}) async {
    try {
      await _family.reviewChildTask(
        familyId: widget.familyId,
        taskId: task.id,
        approve: approve,
      );
      await _load();
    } catch (error) {
      _showError('review child task', error);
    }
  }

  void _showError(String action, Object error) {
    reportAppError(action, error);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(userFacingError)),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'submitted' => 'Needs your review',
        'approved' => 'Approved',
        'rejected' => 'Needs changes',
        _ => 'In progress',
      };

  @override
  Widget build(BuildContext context) {
    final awaitingReview = _tasks.where((task) => task.status == 'submitted');
    final visibleTasks = _tasks
        .where((task) => _taskFilter == 'all' || task.taskType == _taskFilter)
        .toList()
      ..sort((a, b) {
        final aDate = (a.dueAt ?? a.createdAt).toLocal();
        final bDate = (b.dueAt ?? b.createdAt).toLocal();
        return aDate.compareTo(bDate);
      });
    final tasksByDate = <DateTime, List<ChildTask>>{};
    for (final task in visibleTasks) {
      final date = (task.dueAt ?? task.createdAt).toLocal();
      final dateKey = DateTime(date.year, date.month, date.day);
      tasksByDate.putIfAbsent(dateKey, () => []).add(task);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} · Tasks'),
        actions: [
          IconButton(
            tooltip: 'Refresh tasks',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTask,
        icon: const Icon(Icons.add_task),
        label: const Text('Assign task'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  GlassCard(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.checklist_rounded,
                          size: 34,
                          color: Color(0xFF286F69),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_tasks.length} assigned task${_tasks.length == 1 ? '' : 's'}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                awaitingReview.isEmpty
                                    ? 'Assign a task or check recent progress.'
                                    : '${awaitingReview.length} submission${awaitingReview.length == 1 ? '' : 's'} waiting for approval',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.wifi_off),
                        title: Text(_error!),
                        trailing: IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final filter in const ['all', 'task', 'homework'])
                        ChoiceChip(
                          label: Text(switch (filter) {
                            'task' => 'Tasks',
                            'homework' => 'Homework',
                            _ => 'All',
                          }),
                          selected: _taskFilter == filter,
                          onSelected: (_) =>
                              setState(() => _taskFilter = filter),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (visibleTasks.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.task_alt, size: 42),
                            SizedBox(height: 8),
                            Text(
                              'No tasks yet',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text('Assign a small goal and reward progress.'),
                          ],
                        ),
                      ),
                    )
                  else
                    ...tasksByDate.entries.expand(
                      (entry) => [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                          child: Text(
                            DateUtils.isSameDay(entry.key, DateTime.now())
                                ? 'Today'
                                : DateFormat('EEEE, MMM d').format(entry.key),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        ...entry.value.map(_buildTaskCard),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildTaskCard(ChildTask task) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    task.taskType == 'homework'
                        ? Icons.menu_book_outlined
                        : Icons.check_circle_outline,
                    color: const Color(0xFF347A75),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (task.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(task.description),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '${task.taskType == 'homework' ? 'Homework' : 'Task'} · ${task.points} points · ${_statusLabel(task.status)}'
                          '${task.dueAt == null ? '' : ' · Due ${DateFormat('MMM d').format(task.dueAt!.toLocal())}'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (task.submissionPhotoPath != null) ...[
                const SizedBox(height: 12),
                FutureBuilder<String>(
                  future: _family.createTaskPhotoUrl(task.submissionPhotoPath!),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text(userFacingError);
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        snapshot.data!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
                if (task.submissionNote?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(task.submissionNote!),
                  ),
              ],
              if (task.status == 'submitted')
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _reviewTask(task, approve: false),
                        child: const Text('Needs changes'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _reviewTask(task, approve: true),
                        icon: const Icon(Icons.check),
                        label: const Text('Approve'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
