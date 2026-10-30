import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent/screens/rewards_screen.dart';
import 'package:shared/shared.dart';

ExtraTimeRequest request(
        {String status = 'pending', int? minutes, String child = 'one'}) =>
    ExtraTimeRequest(
        id: child,
        familyId: 'family',
        childId: child,
        packageName: 'books',
        appLabel: 'Books',
        requestedMinutes: 30,
        grantedMinutes: minutes,
        status: status,
        requestedAt: DateTime(2026, 10, 24, 10),
        resolvedAt: status == 'pending' ? null : DateTime(2026, 10, 24, 11),
        resolvedBy: status == 'pending' ? null : 'parent');
ChildTask task({String status = 'submitted'}) => ChildTask(
    id: 'task',
    familyId: 'family',
    childId: 'one',
    title: 'Read a chapter',
    description: '',
    taskType: 'homework',
    dueAt: null,
    points: 10,
    status: status,
    createdAt: DateTime(2026, 10, 24),
    submissionPhotoPath: null,
    submissionNote: null);

class RewardsFamily extends FamilyService {
  final requests = {'one': request(), 'two': request(child: 'two')};
  var currentTask = task();
  int? approvedMinutes;
  bool? taskApproved;
  @override
  Future<List<ExtraTimeRequest>> fetchExtraTimeRequests(
          {required String familyId, String? childId}) async =>
      [requests[childId]!];
  @override
  Future<List<ChildTask>> fetchChildTasks(
          {required String familyId, String? childId}) async =>
      childId == 'one' ? [currentTask] : [];
  @override
  Future<ChildStreak?> fetchChildStreak(String childId) async => null;
  @override
  Future<void> resolveExtraTimeRequest(
      {required String familyId,
      required String id,
      required bool approve,
      int? grantedMinutes}) async {
    approvedMinutes = grantedMinutes;
    requests[id] = request(
        child: id,
        status: approve ? 'approved' : 'denied',
        minutes: grantedMinutes);
  }

  @override
  Future<void> reviewChildTask(
      {required String familyId,
      required String taskId,
      required bool approve}) async {
    taskApproved = approve;
    currentTask = task(status: approve ? 'approved' : 'rejected');
  }
}

const children = [
  FamilyMember(
      id: '1',
      familyId: 'family',
      profileId: 'one',
      profile: Profile(id: 'one', role: 'child', displayName: 'Alex')),
  FamilyMember(
      id: '2',
      familyId: 'family',
      profileId: 'two',
      profile: Profile(id: 'two', role: 'child', displayName: 'Sam'))
];
Widget frame(RewardsFamily family) => MaterialApp(
    theme: AppPalette.theme(),
    home: RewardsScreen(
        familyId: 'family', children: children, familyService: family));
void main() {
  testWidgets('parent edits minutes, approves a reward, and sees history',
      (tester) async {
    final family = RewardsFamily();
    await tester.pumpWidget(frame(family));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '15');
    await tester.tap(find.text('Approve & give reward'));
    await tester.pumpAndSettle();
    expect(family.approvedMinutes, 15);
    expect(find.text('Approve'), findsNothing);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('15 min approved by parent'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'child selection does not mix requests and tasks award points separately',
      (tester) async {
    final family = RewardsFamily();
    await tester.pumpWidget(frame(family));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks & points'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Approve & award points'));
    await tester.tap(find.text('Approve & award points'));
    await tester.pumpAndSettle();
    expect(family.taskApproved, true);
    expect(family.approvedMinutes, null);
    expect(find.text('Approve & award points'), findsNothing);
    await tester.ensureVisible(find.text('Alex'));
    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sam').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline').last);
    await tester.pumpAndSettle();
    expect(family.requests['two']!.status, 'denied');
    expect(family.requests['one']!.status, 'pending');
    await tester.pumpWidget(const SizedBox());
  });
}
