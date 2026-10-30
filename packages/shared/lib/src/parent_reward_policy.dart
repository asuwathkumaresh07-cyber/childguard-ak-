import 'models.dart';

bool isParentApprovedReward(
        ExtraTimeRequest request, String? parentId, DateTime now) =>
    parentId != null &&
    request.status == 'approved' &&
    request.resolvedBy == parentId &&
    request.resolvedAt != null &&
    !request.resolvedAt!.isAfter(now) &&
    request.grantedMinutes != null &&
    request.grantedMinutes! > 0 &&
    request.grantedMinutes! <= 120;

Map<String, int> parentApprovedExtraSeconds(
    List<ExtraTimeRequest> requests, String? parentId, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final result = <String, int>{};
  for (final request in requests) {
    if (!isParentApprovedReward(request, parentId, now) ||
        request.resolvedAt!.toLocal().isBefore(today)) {
      continue;
    }
    result.update(request.packageName,
        (seconds) => seconds + request.grantedMinutes! * 60,
        ifAbsent: () => request.grantedMinutes! * 60);
  }
  return result;
}

Set<String> parentApprovedAppAccess(
        List<ExtraTimeRequest> requests, String? parentId, DateTime now) =>
    requests
        .where((request) =>
            isParentApprovedReward(request, parentId, now) &&
            request.resolvedAt!
                .add(Duration(minutes: request.grantedMinutes!))
                .isAfter(now))
        .map((request) => request.packageName)
        .toSet();
