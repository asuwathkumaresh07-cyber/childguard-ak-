import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/location_radar.dart';
import '../widgets/user_error.dart';

class ChildPlansScreen extends StatefulWidget {
  const ChildPlansScreen({
    super.key,
    required this.familyId,
    required this.childId,
    required this.childName,
    this.showOther = false,
    this.extraSections = const [],
  });

  final String familyId;
  final String childId;
  final String childName;
  final bool showOther;
  final List<Widget> extraSections;

  @override
  State<ChildPlansScreen> createState() => _ChildPlansScreenState();
}

class _ChildPlansScreenState extends State<ChildPlansScreen> {
  final _family = FamilyService();
  bool _loading = true;
  String? _error;
  String? _locationError;
  ChildLocation? _location;
  List<ChildLocation> _locationHistory = [];
  List<FamilyZone> _zones = [];
  List<ZoneAppRule> _zoneRules = [];
  List<ChildMoodCheckin> _moods = [];
  List<ZoneEvent> _zoneEvents = [];
  ChildStreak? _streak;
  ChildAutonomySettings? _autonomy;
  RealtimeChannel? _locationRealtimeSub;
  Timer? _locationPoll;
  bool _locationRefreshInProgress = false;

  @override
  void initState() {
    super.initState();
    _locationRealtimeSub = _family.subscribeToChildLocations(
      widget.childId,
      _onLocationUpdate,
    );
    _locationPoll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshLocation()),
    );
    _load();
  }

  @override
  void dispose() {
    _locationRealtimeSub?.unsubscribe();
    _locationPoll?.cancel();
    super.dispose();
  }

  void _onLocationUpdate(ChildLocation location) {
    if (!mounted ||
        location.familyId != widget.familyId ||
        location.childId != widget.childId ||
        (_location != null &&
            !location.recordedAt.isAfter(_location!.recordedAt))) {
      return;
    }
    setState(() {
      _location = location;
      _locationHistory = [
        location,
        ..._locationHistory.where((item) => item.id != location.id),
      ].take(48).toList();
      _locationError = null;
    });
  }

  Future<void> _refreshLocation() async {
    if (!_family.isUsingSupabase || _locationRefreshInProgress) return;
    _locationRefreshInProgress = true;
    try {
      final location = await _family.fetchLatestChildLocation(widget.childId);
      if (!mounted) return;
      setState(() {
        if (location != null &&
            location.familyId == widget.familyId &&
            location.childId == widget.childId &&
            (_location == null ||
                location.recordedAt.isAfter(_location!.recordedAt))) {
          _location = location;
        }
        _locationError = null;
      });
      try {
        final history = await _family.fetchChildLocationHistory(widget.childId);
        if (!mounted) return;
        setState(() {
          _locationHistory = history
              .where((sample) =>
                  sample.familyId == widget.familyId &&
                  sample.childId == widget.childId)
              .toList();
          _locationError = null;
        });
      } catch (error) {
        reportAppError('refresh child location history', error);
        if (mounted) setState(() => _locationError = userFacingError);
      }
    } catch (error) {
      reportAppError('refresh child location', error);
      if (mounted) setState(() => _locationError = userFacingError);
    } finally {
      _locationRefreshInProgress = false;
    }
  }

  Future<void> _openLocationInMaps() async {
    final location = _location;
    if (location == null) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${location.latitude},${location.longitude}',
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showMessage(userFacingError);
      }
    } catch (error) {
      _showError('open map', error);
    }
  }

  Future<void> _load() async {
    if (!_family.isUsingSupabase) {
      reportAppError(
        'load child plans',
        StateError('The family service is not connected.'),
      );
      setState(() {
        _loading = false;
        _error = userFacingError;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_refreshLocation());
    try {
      final values = await Future.wait([
        _family.fetchFamilyZones(widget.familyId),
        _family.fetchZoneAppRules(widget.familyId),
        _family.fetchChildMoodCheckins(
          familyId: widget.familyId,
          childId: widget.childId,
        ),
        _family.fetchChildStreak(widget.childId),
        _family.fetchZoneEvents(
          familyId: widget.familyId,
          childId: widget.childId,
        ),
        _family.fetchChildAutonomySettings(
          familyId: widget.familyId,
          childId: widget.childId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _zones = values[0] as List<FamilyZone>;
        _zoneRules = values[1] as List<ZoneAppRule>;
        _moods = values[2] as List<ChildMoodCheckin>;
        _streak = values[3] as ChildStreak?;
        _zoneEvents = values[4] as List<ZoneEvent>;
        _autonomy = values[5] as ChildAutonomySettings;
        _loading = false;
      });
    } catch (error) {
      reportAppError('load child plans', error);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = userFacingError;
        });
      }
    }
  }

  Future<void> _createZone() async {
    final location = _location;
    final name = TextEditingController();
    final latitude = TextEditingController(
      text: location?.latitude.toStringAsFixed(6) ?? '',
    );
    final longitude = TextEditingController(
      text: location?.longitude.toStringAsFixed(6) ?? '',
    );
    var type = 'school';
    var radius = 550;
    String? validationMessage;
    try {
      final values = await showDialog<(String, String, int, double, double)>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add a known place'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Place name',
                      hintText: 'e.g. Green Valley School',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Place type'),
                    items: const [
                      DropdownMenuItem(value: 'home', child: Text('Home')),
                      DropdownMenuItem(
                        value: 'school',
                        child: Text('School'),
                      ),
                      DropdownMenuItem(
                        value: 'tuition',
                        child: Text('Tuition center'),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text('Other place'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: radius,
                    decoration:
                        const InputDecoration(labelText: 'Safe-zone size'),
                    items: const [500, 550, 600]
                        .map(
                          (meters) => DropdownMenuItem(
                            value: meters,
                            child: Text('$meters meters'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => radius = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Location coordinates',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            hintText: '12.9716',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            hintText: '77.5946',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Coordinates are prefilled from the latest child location. You can replace them with a known place’s coordinates.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (location != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() {
                          latitude.text = location.latitude.toStringAsFixed(6);
                          longitude.text =
                              location.longitude.toStringAsFixed(6);
                        }),
                        icon: const LiveIcon(Icons.my_location, size: 18),
                        label: const Text("Use child's latest location"),
                      ),
                    ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
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
                  final lat = double.tryParse(latitude.text.trim());
                  final lon = double.tryParse(longitude.text.trim());
                  if (name.text.trim().isEmpty) {
                    setDialogState(
                      () => validationMessage = 'Enter a place name.',
                    );
                  } else if (lat == null ||
                      lon == null ||
                      lat < -90 ||
                      lat > 90 ||
                      lon < -180 ||
                      lon > 180) {
                    setDialogState(
                      () => validationMessage =
                          'Enter valid latitude and longitude values.',
                    );
                  } else {
                    Navigator.pop(
                      context,
                      (
                        name.text.trim(),
                        type,
                        radius,
                        lat,
                        lon,
                      ),
                    );
                  }
                },
                child: const Text('Save place'),
              ),
            ],
          ),
        ),
      );
      if (values == null) return;
      await _family.saveFamilyZone(
        familyId: widget.familyId,
        name: values.$1,
        zoneType: values.$2,
        radiusMeters: values.$3,
        latitude: values.$4,
        longitude: values.$5,
      );
      await _load();
    } catch (error) {
      _showError('save zone', error);
    } finally {
      name.dispose();
      latitude.dispose();
      longitude.dispose();
    }
  }

  Future<void> _addZoneRule(FamilyZone zone) async {
    final package = TextEditingController();
    final label = TextEditingController();
    try {
      final values = await showDialog<(String, String)>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Restrict apps in ${zone.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'App name'),
              ),
              TextField(
                controller: package,
                decoration: const InputDecoration(
                  labelText: 'Android package name',
                  hintText: 'com.example.app',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (package.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  (package.text.trim(), label.text.trim()),
                );
              },
              child: const Text('Add restriction'),
            ),
          ],
        ),
      );
      if (values == null) return;
      await _family.saveZoneAppRule(
        familyId: widget.familyId,
        zoneId: zone.id,
        packageName: values.$1,
        appLabel: values.$2,
      );
      await _load();
    } catch (error) {
      _showError('add zone restriction', error);
    } finally {
      package.dispose();
      label.dispose();
    }
  }

  Future<void> _configureAutonomy() async {
    final current = _autonomy ??
        ChildAutonomySettings(
          childId: widget.childId,
          familyId: widget.familyId,
          enabled: false,
          minTrustScore: 80,
          dailyExtraMinutesCap: 15,
        );
    const enabled = false;
    final minimumScore = current.minTrustScore.toDouble();
    final cap = TextEditingController(
      text: current.dailyExtraMinutesCap.toString(),
    );
    try {
      final values = await showDialog<(bool, int, int)>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Parent-approved time rewards'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Extra screen time and temporary app access need your approval in Rewards & approvals. Children can earn their own cosmetic badges and themes. Confirm to also turn off the older trust-based automatic-time setting.'),
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
                  final capMinutes = int.tryParse(cap.text) ?? 0;
                  if (capMinutes < 1 || capMinutes > 120) return;
                  Navigator.pop(
                    context,
                    (enabled, minimumScore.round(), capMinutes),
                  );
                },
                child: const Text('Require parent approval'),
              ),
            ],
          ),
        ),
      );
      if (values == null) return;
      await _family.saveChildAutonomySettings(
        familyId: widget.familyId,
        childId: widget.childId,
        enabled: values.$1,
        minTrustScore: values.$2,
        dailyExtraMinutesCap: values.$3,
      );
      if (mounted) {
        setState(() {
          _autonomy = ChildAutonomySettings(
            childId: widget.childId,
            familyId: widget.familyId,
            enabled: values.$1,
            minTrustScore: values.$2,
            dailyExtraMinutesCap: values.$3,
          );
        });
      }
    } catch (error) {
      _showError('save autonomy settings', error);
    } finally {
      cap.dispose();
    }
  }

  Future<void> _removeZone(FamilyZone zone) async {
    try {
      await _family.removeFamilyZone(widget.familyId, zone.id);
      await _load();
    } catch (error) {
      _showError('remove zone', error);
    }
  }

  Future<void> _removeRule(ZoneAppRule rule) async {
    try {
      await _family.removeZoneAppRule(rule.id);
      await _load();
    } catch (error) {
      _showError('remove zone restriction', error);
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

  FamilyZone? get _activeZone {
    final current = _location;
    if (current == null) return null;
    for (final zone in _zones) {
      if (_distanceMeters(
            current.latitude,
            current.longitude,
            zone.latitude,
            zone.longitude,
          ) <=
          zone.radiusMeters) {
        return zone;
      }
    }
    return null;
  }

  double _distanceMeters(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
  ) {
    const earthRadius = 6371000.0;
    final latDelta = (latitude2 - latitude1) * math.pi / 180;
    final lonDelta = (longitude2 - longitude1) * math.pi / 180;
    final a = math.pow(math.sin(latDelta / 2), 2) +
        math.cos(latitude1 * math.pi / 180) *
            math.cos(latitude2 * math.pi / 180) *
            math.pow(math.sin(lonDelta / 2), 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _locationFreshness(ChildLocation? location) {
    if (location == null) return 'Waiting';
    final age = DateTime.now().difference(location.recordedAt.toLocal());
    if (age.inMinutes < 3) return 'Live';
    if (age.inMinutes < 20) return 'Recent';
    return 'Stale';
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AppLoadingView(
          message: widget.showOther
              ? 'Loading child settings'
              : 'Loading location and zones',
          icon: widget.showOther ? Icons.settings : Icons.location_on_outlined);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(
              child: ListTile(
                leading: const LiveIcon(Icons.info_outline),
                title: Text(_error!),
                trailing: IconButton(
                  tooltip: 'Retry',
                  onPressed: _load,
                  icon: const LiveIcon(Icons.refresh),
                ),
              ),
            ),
          if (!widget.showOther) ...[
            _sectionTitle(
              'Location & zones',
              trailing: IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const LiveIcon(Icons.refresh),
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const LiveIcon(Icons.radar, color: Color(0xFF172B4D)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _location == null
                              ? 'Waiting for location'
                              : '${widget.childName} · ${_locationFreshness(_location)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_location != null)
                        Text(
                          DateFormat('h:mm a')
                              .format(_location!.recordedAt.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LocationRadar(
                    location: _location,
                    history: _locationHistory,
                    zones: _zones,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      LiveIcon(
                        _activeZone == null
                            ? Icons.near_me_outlined
                            : Icons.location_on,
                        size: 18,
                        color: _activeZone == null
                            ? const Color(0xFF172B4D)
                            : const Color(0xFF172B4D),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _location == null
                              ? 'Waiting for the first update. Turn on “Share my location” in the Child app.'
                              : _locationFreshness(_location) == 'Stale'
                                  ? 'Last seen ${_activeZone == null ? 'outside saved places' : 'at ${_activeZone!.name}'} · update is stale'
                                  : _activeZone == null
                                      ? 'Unknown place · outside saved places'
                                      : 'At ${_activeZone!.name}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_location?.accuracyMeters != null)
                        Text(
                          '±${_location!.accuracyMeters!.round()} m',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  if (_locationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      userFacingError,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _location == null ? null : _openLocationInMaps,
                        icon: const LiveIcon(Icons.map_outlined),
                        label: const Text('View location'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _createZone,
                        icon: const LiveIcon(Icons.add_location_alt),
                        label: const Text('Add known place'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_zones.isEmpty)
              const Text(
                'No saved places yet. Add Home, School, or Tuition to see whether your child is at a known place.',
              )
            else
              ..._zones.map((zone) {
                final rules = _zoneRules.where((r) => r.zoneId == zone.id);
                return Card(
                  child: ExpansionTile(
                    title: Text(zone.name),
                    subtitle: Text(
                      '${zone.zoneType} · ${zone.radiusMeters} m radius',
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete zone',
                      onPressed: () => _removeZone(zone),
                      icon: const LiveIcon(Icons.delete_outline),
                    ),
                    children: [
                      ...rules.map(
                        (rule) => ListTile(
                          dense: true,
                          title: Text(
                            rule.appLabel.isEmpty
                                ? rule.packageName
                                : rule.appLabel,
                          ),
                          subtitle: Text(rule.packageName),
                          trailing: IconButton(
                            onPressed: () => _removeRule(rule),
                            icon: const LiveIcon(Icons.remove_circle_outline),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _addZoneRule(zone),
                        icon: const LiveIcon(Icons.add),
                        label: const Text('Restrict an app in this zone'),
                      ),
                    ],
                  ),
                );
              }),
            if (_zoneEvents.isNotEmpty) ...[
              _sectionTitle('Recent zone events'),
              ..._zoneEvents.take(10).map((event) {
                final zone = _zones.where((item) => item.id == event.zoneId);
                final zoneName = zone.isEmpty ? 'Zone' : zone.first.name;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: LiveIcon(
                    event.eventType == 'off_task_app'
                        ? Icons.warning_amber
                        : Icons.place,
                  ),
                  title: Text(
                    event.eventType == 'off_task_app'
                        ? '${event.packageName ?? 'App'} in $zoneName'
                        : '${event.eventType} $zoneName',
                  ),
                  subtitle: Text(
                    DateFormat('MMM d, h:mm a')
                        .format(event.occurredAt.toLocal()),
                  ),
                  trailing: event.eventType == 'off_task_app' && zone.isNotEmpty
                      ? IconButton(
                          tooltip: 'Restrict this app in this zone',
                          onPressed: () => _addZoneRule(zone.first),
                          icon: const LiveIcon(Icons.block),
                        )
                      : null,
                );
              }),
            ],
          ],
          if (widget.showOther) ...[
            ...widget.extraSections,
            if (_streak != null)
              Card(
                child: ListTile(
                  leading: const LiveIcon(Icons.local_fire_department),
                  title: Text(
                    '${_streak!.currentStreak} approved-task streak · ${_streak!.totalPoints} points',
                  ),
                  subtitle: Text(
                    'Best: ${_streak!.bestStreak} tasks · '
                    '${_streak!.bonusTimeMinutes} bonus minutes · '
                    '${_streak!.appUnlockCredits} app unlocks available',
                  ),
                ),
              ),
            Card(
              child: ListTile(
                leading: const LiveIcon(Icons.tune),
                title: const Text('Parent approval for time rewards'),
                subtitle: Text(
                  _autonomy?.enabled == true
                      ? 'An older automatic-time setting is still saved. Turn it off for older app versions.'
                      : 'Review screen-time and temporary-access requests in Rewards & approvals.',
                ),
                trailing: IconButton(
                  tooltip: 'Parent approval policy',
                  onPressed: _configureAutonomy,
                  icon: const LiveIcon(Icons.settings),
                ),
              ),
            ),
            _sectionTitle('Recent mood check-ins'),
            if (_moods.isEmpty)
              const Text('No mood check-ins have been submitted.')
            else
              ..._moods.take(10).map(
                    (mood) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const LiveIcon(Icons.mood),
                      title: Text(mood.mood),
                      subtitle: Text(
                        '${DateFormat('MMM d, h:mm a').format(mood.createdAt.toLocal())}'
                        '${mood.note.isEmpty ? '' : ' · ${mood.note}'}',
                      ),
                    ),
                  ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
