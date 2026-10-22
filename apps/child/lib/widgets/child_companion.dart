import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:not_static_icons/not_static_icons.dart' as pets;
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'companion_break.dart';

enum CompanionPet { cat, dog, bird }

extension CompanionPetLabel on CompanionPet {
  String get petName => switch (this) {
        CompanionPet.cat => 'Milo',
        CompanionPet.dog => 'Buddy',
        CompanionPet.bird => 'Pip'
      };
  String get label => switch (this) {
        CompanionPet.cat => 'Milo the cat',
        CompanionPet.dog => 'Buddy the puppy',
        CompanionPet.bird => 'Pip the bird'
      };
}

class CompanionPetAvatar extends StatelessWidget {
  const CompanionPetAvatar({super.key, required this.pet, this.size = 82});
  final CompanionPet pet;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    Widget artwork = switch (pet) {
      CompanionPet.cat => pets.CatIcon(
          size: size * .7,
          color: AppPalette.blue,
          infiniteLoop: !reduced,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2800)),
      CompanionPet.dog => pets.DogIcon(
          size: size * .7,
          color: AppPalette.blue,
          infiniteLoop: !reduced,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2800)),
      CompanionPet.bird => pets.BirdIcon(
          size: size * .7,
          color: AppPalette.blue,
          infiniteLoop: !reduced,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2800)),
    };
    artwork = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: AppPalette.paleBlue,
            borderRadius: BorderRadius.circular(size * .3),
            border: Border.all(color: AppPalette.border)),
        child: Center(child: artwork));
    if (!reduced) {
      artwork = artwork
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .moveY(begin: -2, end: 2, duration: 1800.ms, curve: Curves.easeInOut);
    }
    return Semantics(
        label: pet.label, image: true, child: IgnorePointer(child: artwork));
  }
}

/// Reminders are derived from synced tasks and current device status.
class ChildCompanionCard extends StatefulWidget {
  const ChildCompanionCard(
      {super.key,
      required this.childId,
      required this.tasks,
      required this.vpnEnabled,
      required this.permissionsReady,
      required this.checkInDue,
      required this.onTasks,
      required this.onProtection,
      required this.onPermissions,
      required this.onCheckIn,
      this.hindi = false});
  final String childId;
  final List<ChildTask> tasks;
  final bool vpnEnabled;
  final bool permissionsReady;
  final bool checkInDue;
  final VoidCallback onTasks;
  final VoidCallback onProtection;
  final VoidCallback onPermissions;
  final VoidCallback onCheckIn;
  final bool hindi;

  @override
  State<ChildCompanionCard> createState() => _ChildCompanionCardState();
}

class _ChildCompanionCardState extends State<ChildCompanionCard> {
  CompanionPet _pet = CompanionPet.cat;
  Offset _petOffset = Offset.zero;
  bool _cheering = false;
  Timer? _cheerTimer;
  String get _preferenceKey => 'child_companion_${widget.childId}';
  String _text(String english, String hindi) => widget.hindi ? hindi : english;

  @override
  void initState() {
    super.initState();
    _loadPet();
  }

  @override
  void dispose() {
    _cheerTimer?.cancel();
    super.dispose();
  }

  void _cheer() {
    _cheerTimer?.cancel();
    setState(() => _cheering = true);
    _cheerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _cheering = false);
    });
  }

  Future<void> _loadPet() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferenceKey);
    if (!mounted) return;
    setState(() => _pet =
        CompanionPet.values.where((pet) => pet.name == saved).firstOrNull ??
            CompanionPet.cat);
  }

  Future<void> _choosePet() async {
    final selected = await showModalBottomSheet<CompanionPet>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: SingleChildScrollView(
                    child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_text('Choose your buddy', 'अपना साथी चुनें'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    GridView(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 150 *
                                MediaQuery.textScalerOf(context)
                                    .scale(1)
                                    .clamp(1, 1.5)),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final pet in CompanionPet.values)
                            Semantics(
                                button: true,
                                selected: _pet == pet,
                                child: Material(
                                  color: _pet == pet
                                      ? AppPalette.paleBlue
                                      : Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      side: BorderSide(
                                          color: _pet == pet
                                              ? AppPalette.blue
                                              : AppPalette.border)),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                      onTap: () => Navigator.pop(context, pet),
                                      child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                CompanionPetAvatar(
                                                    pet: pet, size: 58),
                                                const SizedBox(height: 10),
                                                Text(pet.label,
                                                    textAlign:
                                                        TextAlign.center),
                                              ]))),
                                ))
                        ]),
                  ]),
            ))));
    if (selected == null || !mounted) return;
    setState(() => _pet = selected);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, selected.name);
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.tasks
        .where((task) => task.status == 'assigned' || task.status == 'rejected')
        .toList()
      ..sort((a, b) =>
          (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999)));
    final next = pending.firstOrNull;
    late String title;
    late String message;
    if (!widget.vpnEnabled) {
      title = _text('Let’s check your protection', 'अपनी सुरक्षा जाँचें');
      message = _text(
          'Protection is off. Ask your parent for an ON code, then enter it in Focus.',
          'सुरक्षा बंद है। माता-पिता से ON कोड माँगें और Focus में दर्ज करें।');
    } else if (!widget.permissionsReady) {
      title = _text('One more safety step', 'सुरक्षा का एक और कदम');
      message = _text(
          'Usage access or app blocking needs permission. Let’s review your device settings.',
          'उपयोग और ऐप ब्लॉकिंग की अनुमतियाँ जाँचें।');
    } else if (next != null) {
      final overdue =
          next.dueAt != null && next.dueAt!.isBefore(DateTime.now());
      title = _text(
          overdue ? 'A task needs your attention' : 'Ready for your next task?',
          overdue ? 'एक काम पर ध्यान दें' : 'अगले काम के लिए तैयार?');
      message =
          '${next.title}\n${_text('${pending.length} task${pending.length == 1 ? '' : 's'} to do. Take it one step at a time.', '${pending.length} काम बाकी हैं। एक-एक करके करें।')}';
    } else if (widget.checkInDue) {
      title = _text('How are you doing today?', 'आज आप कैसे हैं?');
      message = _text(
          'You can share a quick check-in with your parent, or do it later.',
          'माता-पिता को छोटा चेक-इन भेजें, या बाद में करें।');
    } else {
      title = _text('You’re all caught up!', 'आपके काम पूरे हैं!');
      message = _text(
          'Protection is on and there are no tasks waiting. Enjoy a little break.',
          'सुरक्षा चालू है और कोई काम बाकी नहीं है। थोड़ा आराम करें।');
    }
    return GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(
                _text('${_pet.petName}, your buddy',
                    '${_pet.petName}, आपका साथी'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700))),
        IconButton(
            tooltip: _text('Choose a pet', 'साथी चुनें'),
            onPressed: _choosePet,
            icon: const Icon(Icons.pets_outlined)),
      ]),
      const SizedBox(height: 4),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
            label: _text('Tap or drag your buddy', 'साथी को छुएँ या खींचें'),
            button: true,
            child: GestureDetector(
                onTap: _cheer,
                onPanUpdate: (details) => setState(() => _petOffset = Offset(
                    (_petOffset.dx + details.delta.dx).clamp(-8, 8),
                    (_petOffset.dy + details.delta.dy).clamp(-8, 8))),
                onPanEnd: (_) => setState(() => _petOffset = Offset.zero),
                onPanCancel: () => setState(() => _petOffset = Offset.zero),
                child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    transform: Matrix4.translationValues(
                        _petOffset.dx, _petOffset.dy, 0),
                    child: AnimatedScale(
                        scale: _cheering ? 1.08 : 1,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: CompanionPetAvatar(pet: _pet))))),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              _cheering
                  ? _text('${_pet.petName} is cheering you on!',
                      '${_pet.petName} आपका हौसला बढ़ाता है!')
                  : title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
        ])),
      ]),
      const SizedBox(height: 16),
      GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 112 *
                  MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5)),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _actionTile(
                icon: Icons.checklist_outlined,
                title: _text('My tasks', 'मेरे काम'),
                subtitle:
                    _text('${pending.length} to do', '${pending.length} बाकी'),
                onTap: widget.onTasks),
            _actionTile(
                icon: Icons.shield_outlined,
                title: _text('Protection', 'सुरक्षा'),
                subtitle: _text(widget.vpnEnabled ? 'On' : 'Needs attention',
                    widget.vpnEnabled ? 'चालू' : 'ध्यान दें'),
                onTap: widget.vpnEnabled && !widget.permissionsReady
                    ? widget.onPermissions
                    : widget.onProtection),
            _actionTile(
                icon: Icons.mood,
                title: _text('Check in', 'चेक-इन'),
                subtitle: _text('Feelings & help', 'मन और मदद'),
                onTap: widget.onCheckIn),
            _actionTile(
                icon: Icons.air,
                title: _text('Tiny break', 'छोटा विराम'),
                subtitle: _text('30 calm seconds', '30 शांत सेकंड'),
                onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => CompanionBreakDialog(hindi: widget.hindi))),
          ]),
    ]));
  }

  Widget _actionTile(
          {required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap}) =>
      Material(
        color: AppPalette.background,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppPalette.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LiveIcon(icon, size: 24),
                      const SizedBox(height: 5),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Flexible(
                          child: Text(subtitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall)),
                    ]))),
      );
}

/// Gentle paw motion behind the page, with no wave or ripple layers.
class CompanionBackdrop extends StatelessWidget {
  const CompanionBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: AppPalette.background,
      child: Stack(children: [
        Positioned.fill(
            child: IgnorePointer(
                child: LayoutBuilder(
                    builder: (context, constraints) => Stack(children: [
                          for (var index = 0; index < 4; index++)
                            Positioned(
                              left: constraints.maxWidth *
                                  (index.isEven ? .04 : .82),
                              top: constraints.maxHeight * (.08 + index * .23),
                              child: _floatingPaw(context, index),
                            ),
                        ])))),
        child,
      ]));

  Widget _floatingPaw(BuildContext context, int index) {
    Widget paw = Icon(Icons.pets_outlined,
        size: 34 + index * 3, color: AppPalette.blue.withValues(alpha: .045));
    if (!MediaQuery.disableAnimationsOf(context)) {
      paw = paw
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .moveY(
              begin: -8,
              end: 8,
              duration: Duration(milliseconds: 3400 + index * 400),
              curve: Curves.easeInOut)
          .rotate(
              begin: -.025,
              end: .025,
              duration: Duration(milliseconds: 3400 + index * 400));
    }
    return paw;
  }
}
