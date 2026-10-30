import 'package:flutter/material.dart';
import 'package:shared/shared.dart';
import '../services/activity_rewards.dart';

class ActivityRewardsCard extends StatefulWidget {
  const ActivityRewardsCard(
      {super.key, required this.childId, required this.tasks, this.streak});
  final String childId;
  final List<ChildTask> tasks;
  final ChildStreak? streak;
  @override
  State<ActivityRewardsCard> createState() => _ActivityRewardsCardState();
}

class _ActivityRewardsCardState extends State<ActivityRewardsCard> {
  ActivityProgress? progress;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    ActivityRewards.changed.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(ActivityRewardsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      progress = null;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.childId;
    final result = await ActivityRewards.load(id);
    if (mounted && id == widget.childId) setState(() => progress = result);
  }

  @override
  void dispose() {
    ActivityRewards.changed.removeListener(_load);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final todayPoints = p?.pointsToday(DateTime.now()) ?? 0;
    final activityScore = (todayPoints * 100 / 38).round().clamp(0, 100);
    final approved =
        widget.tasks.where((task) => task.status == 'approved').length;
    final score = widget.tasks.isEmpty
        ? 0
        : (100 * approved / widget.tasks.length).round();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Family Guard · My progress',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text('Today’s activity score: $activityScore/100',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                LinearProgressIndicator(value: activityScore / 100),
                Text('$todayPoints of 38 daily buddy points earned'),
                const SizedBox(height: 12),
                Text('Task activity score: $score/100',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: score / 100),
                Text(
                    '$approved of ${widget.tasks.length} tasks approved by your parent'),
                const SizedBox(height: 12),
                Text(
                    '${widget.streak?.totalPoints ?? 0} approved task points · ${widget.streak?.currentStreak ?? 0}-day streak'),
                Text(
                    'Extra screen time and temporary app access require parent approval. Ask from Focus; your own buddy collectibles below do not need approval.'),
                const Divider(height: 24),
                Text(
                    p == null
                        ? 'Loading buddy points…'
                        : '${p.balance} buddy points available · ${p.earned} earned',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Text(
                    'Earn up to 10 for a quiz, 10 for focus, 5 for breathing, 5 for sharing a check-in, and 2 per water break. One award per activity daily; up to four water breaks.'),
                const SizedBox(height: 8),
                const Text(
                    'Buddy points and collectibles are saved on this device. Parent-approved task rewards sync with your family.'),
                if (p != null) ...[
                  const SizedBox(height: 10),
                  for (final entry in ActivityProgress.rewards.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          switch (entry.key) {
                            'rainbow' => Icons.palette_outlined,
                            'champion' => Icons.workspace_premium,
                            _ => Icons.star_rounded,
                          },
                          color: p.unlocked.contains(entry.key)
                              ? Colors.amber.shade800
                              : Colors.blueGrey),
                      title: Text(ActivityProgress.rewardLabels[entry.key]!),
                      subtitle: Text(p.unlocked.contains(entry.key)
                          ? 'Unlocked'
                          : '${entry.value} buddy points'),
                      trailing: TextButton(
                        onPressed: busy ||
                                (!p.unlocked.contains(entry.key) &&
                                    p.balance < entry.value)
                            ? null
                            : () async {
                                setState(() => busy = true);
                                try {
                                  await ActivityRewards.redeem(
                                      widget.childId, entry.key);
                                } finally {
                                  if (mounted) setState(() => busy = false);
                                }
                              },
                        child: Text(p.activeReward == entry.key
                            ? 'Equipped'
                            : p.unlocked.contains(entry.key)
                                ? 'Equip'
                                : 'Unlock'),
                      ),
                    ),
                ],
              ],
            )));
  }
}
