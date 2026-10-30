import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'companion_pet.dart';

enum PetBehavior { curious, walking, waving, jumping, playing, thinking }

void registerCompanionPetLicense() {
  LicenseRegistry.addLicense(() async* {
    final text =
        await rootBundle.loadString('assets/pets/openpets/LICENSE.txt');
    yield LicenseEntryWithLineBreaks([
      'OpenPets cat, Vincent Hamster, Luna TechBot, Elara and Teddy artwork'
    ], text);
  });
}

/// Plays the downloaded OpenPets atlas unchanged. No animal artwork is drawn here.
class AnimatedCompanionPet extends StatefulWidget {
  const AnimatedCompanionPet(
      {super.key,
      required this.pet,
      this.size = 112,
      this.behavior = PetBehavior.curious,
      this.facingLeft = false});
  final CompanionPet pet;
  final double size;
  final PetBehavior behavior;
  final bool facingLeft;
  @override
  State<AnimatedCompanionPet> createState() => _AnimatedCompanionPetState();
}

class _AnimatedCompanionPetState extends State<AnimatedCompanionPet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frames = AnimationController(vsync: this);
  // Published atlas definitions from OpenPets reaction-animation-mapping.ts.
  ({int row, int count, int duration}) get _clip => switch (widget.behavior) {
        PetBehavior.curious => (row: 0, count: 6, duration: 5500),
        PetBehavior.walking => (
            row: widget.facingLeft ? 2 : 1,
            count: 8,
            duration: 1060
          ),
        PetBehavior.waving => (row: 3, count: 4, duration: 700),
        PetBehavior.jumping => (row: 4, count: 5, duration: 840),
        PetBehavior.playing => (row: 6, count: 6, duration: 1300),
        PetBehavior.thinking => (row: 8, count: 6, duration: 1030),
      };

  void _syncMotion() {
    _frames.stop();
    _frames.duration = Duration(milliseconds: _clip.duration);
    _frames.value = 0;
    if (!MediaQuery.disableAnimationsOf(context)) _frames.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(AnimatedCompanionPet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pet != widget.pet ||
        oldWidget.behavior != widget.behavior ||
        oldWidget.facingLeft != widget.facingLeft) {
      _syncMotion();
    }
  }

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.size;
    final height = widget.size * 208 / 192;
    return RepaintBoundary(
        child: AnimatedBuilder(
            animation: _frames,
            builder: (context, _) {
              final clip = _clip;
              final frame =
                  (_frames.value * clip.count).floor().clamp(0, clip.count - 1);
              return ClipRect(
                  child: SizedBox(
                      width: width,
                      height: height,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: width * 8,
                        maxWidth: width * 8,
                        minHeight: height * widget.pet.sheetRows,
                        maxHeight: height * widget.pet.sheetRows,
                        child: Transform.translate(
                            offset: Offset(-frame * width, -clip.row * height),
                            child: Image.asset(widget.pet.assetPath,
                                width: width * 8,
                                height: height * widget.pet.sheetRows,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                                gaplessPlayback: true,
                                excludeFromSemantics: true)),
                      )));
            }));
  }
}
