import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'companion_pet.dart';
import 'animated_companion_pet.dart';
import '../services/activity_rewards.dart';

/// An in-app companion that stays above scrolling pages and navigation.
class FloatingPet extends StatefulWidget {
  const FloatingPet(
      {super.key, required this.child, this.childId, this.message, this.onTap});
  final Widget child;
  final String? childId;
  final String? message;
  final VoidCallback? onTap;
  @override
  State<FloatingPet> createState() => _FloatingPetState();
}

class _FloatingPetState extends State<FloatingPet> with WidgetsBindingObserver {
  static const _width = 116.0;
  static const _height = 144.0;
  static const _routine = [
    PetBehavior.walking,
    PetBehavior.waving,
    PetBehavior.jumping,
    PetBehavior.walking,
    PetBehavior.playing,
    PetBehavior.jumping,
    PetBehavior.walking,
    PetBehavior.waving
  ];
  Offset position = Offset.zero;
  CompanionPet pet = CompanionPet.hamster;
  PetBehavior behavior = PetBehavior.waving;
  Timer? timer;
  int turn = 0;
  bool dragging = false;
  bool facingLeft = false;
  Size bounds = Size.zero;
  bool _positionedAtCorner = false;
  String? _reward;
  bool _foreground = true;
  int _walkStep = 0;
  static const _directions = [
    Offset(-80, 0),
    Offset(0, -72),
    Offset(80, 0),
    Offset(0, 72)
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    petSelectionChanged.addListener(_loadPet);
    ActivityRewards.changed.addListener(_loadPet);
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _act());
    _loadPet();
  }

  @override
  void didUpdateWidget(FloatingPet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      _positionedAtCorner = false;
      _walkStep = 0;
      _loadPet();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  Future<void> _loadPet() async {
    final id = widget.childId;
    if (id == null) return;
    final selected = await loadCompanionPet(id);
    final progress = await ActivityRewards.load(id);
    if (!mounted || id != widget.childId) return;
    if (selected != pet || progress.activeReward != _reward) {
      setState(() {
        pet = selected;
        _reward = progress.activeReward;
      });
    }
  }

  Offset _clamp(Offset value) => Offset(
      value.dx.clamp(0, math.max(0, bounds.width - _width)).toDouble(),
      value.dy.clamp(0, math.max(0, bounds.height - _height)).toDouble());
  void _act() {
    if (!mounted || !_foreground) return;
    _loadPet();
    if (dragging || MediaQuery.disableAnimationsOf(context)) return;
    setState(() {
      behavior = _routine[turn % _routine.length];
      turn++;
      if (behavior == PetBehavior.walking) {
        final delta = _directions[_walkStep++ % _directions.length];
        var next = _clamp(position + delta);
        if (next == position) next = _clamp(position - delta);
        if (next.dx != position.dx) facingLeft = next.dx < position.dx;
        position = next;
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    petSelectionChanged.removeListener(_loadPet);
    ActivityRewards.changed.removeListener(_loadPet);
    super.dispose();
  }

  String get _caption =>
      widget.message ??
      switch (behavior) {
        PetBehavior.walking => 'Exploring…',
        PetBehavior.waving => 'Saying hello!',
        PetBehavior.jumping => 'Little jump!',
        PetBehavior.playing => 'Let’s play!',
        PetBehavior.curious => '${pet.petName} is curious',
        PetBehavior.thinking => 'Thinking...',
      };

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (widget.childId != null)
          Positioned.fill(child:
              SafeArea(child: LayoutBuilder(builder: (context, constraints) {
            bounds = constraints.biggest;
            if (!_positionedAtCorner && bounds.width > 0 && bounds.height > 0) {
              _positionedAtCorner = true;
              position = _clamp(Offset(
                bounds.width - _width - 12,
                bounds.height - _height - 16,
              ));
            }
            final p = _clamp(position);
            final reduced = MediaQuery.disableAnimationsOf(context);
            return Stack(children: [
              AnimatedPositioned(
                duration: dragging || reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 2900),
                curve: Curves.linear,
                left: p.dx,
                top: p.dy,
                child: Semantics(
                    label:
                        '${pet.label}. Drag to move. ${widget.onTap == null ? 'Tap to play.' : 'Tap for reminders and check-ins.'}',
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => setState(() {
                        dragging = true;
                        behavior = PetBehavior.playing;
                      }),
                      onPanUpdate: (d) => setState(() {
                        if (d.delta.dx.abs() > 1) facingLeft = d.delta.dx < 0;
                        position = _clamp(position + d.delta);
                      }),
                      onPanEnd: (_) => setState(() => dragging = false),
                      onPanCancel: () => setState(() => dragging = false),
                      onTap: () {
                        setState(() => behavior =
                            behavior == PetBehavior.playing
                                ? PetBehavior.waving
                                : PetBehavior.playing);
                        widget.onTap?.call();
                      },
                      child: SizedBox(
                          width: _width,
                          height: _height,
                          child: Column(children: [
                            Stack(alignment: Alignment.topCenter, children: [
                              if (_reward == 'rainbow')
                                Container(
                                    width: 106,
                                    height: 106,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(colors: [
                                          Colors.pink.shade100,
                                          Colors.cyan.shade100,
                                          Colors.amber.shade100
                                        ]))),
                              AnimatedCompanionPet(
                                  pet: pet,
                                  behavior: behavior,
                                  facingLeft: facingLeft,
                                  size: 112),
                              if (_reward == 'star' || _reward == 'champion')
                                Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Icon(
                                        _reward == 'star'
                                            ? Icons.star_rounded
                                            : Icons.workspace_premium,
                                        color: Colors.amber.shade700,
                                        size: 28)),
                            ]),
                            Material(
                                color: Colors.white.withValues(alpha: .95),
                                borderRadius: BorderRadius.circular(12),
                                elevation: 1,
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 4),
                                    child: Text(_caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF34516A))))),
                          ])),
                    )),
              )
            ]);
          }))),
      ]);
}
