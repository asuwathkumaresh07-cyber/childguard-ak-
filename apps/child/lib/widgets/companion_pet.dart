import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

final petSelectionChanged = ValueNotifier<int>(0);

/// Smiling V2 companions and the original cat share one animation contract.
/// `corgi` is retained only to read older saved preferences.
enum CompanionPet { corgi, cat, pajamas, summer, hamster, robot, fox, teddy }

extension CompanionPetLabel on CompanionPet {
  String get petName => switch (this) {
        CompanionPet.hamster => 'Pip',
        CompanionPet.robot => 'Luna',
        CompanionPet.fox => 'Elara',
        CompanionPet.teddy => 'Teddy',
        _ => 'Milo',
      };
  int get sheetRows => 11;
  String get outfitLabel => switch (this) {
        CompanionPet.corgi => 'Milo in a blue hoodie',
        CompanionPet.cat => 'Blue hoodie',
        CompanionPet.pajamas => 'Cozy pajamas',
        CompanionPet.summer => 'Summer outfit',
        CompanionPet.hamster => 'Pip · Happy hamster',
        CompanionPet.robot => 'Luna · Smiling robot',
        CompanionPet.fox => 'Elara · Friendly fox',
        CompanionPet.teddy => 'Teddy · Cheerful bear',
      };
  String get label => switch (this) {
        CompanionPet.corgi => 'Milo in a blue hoodie',
        CompanionPet.cat => 'Milo in a blue hoodie',
        CompanionPet.pajamas => 'Milo in cozy pajamas',
        CompanionPet.summer => 'Milo in a summer outfit',
        CompanionPet.hamster => 'Pip the happy hamster',
        CompanionPet.robot => 'Luna the smiling robot',
        CompanionPet.fox => 'Elara the friendly fox',
        CompanionPet.teddy => 'Teddy the cheerful bear',
      };
  String get assetPath => switch (this) {
        CompanionPet.corgi => 'assets/pets/openpets/hoodie.webp',
        CompanionPet.cat => 'assets/pets/openpets/hoodie.webp',
        CompanionPet.pajamas => 'assets/pets/openpets/pajamas.webp',
        CompanionPet.summer => 'assets/pets/openpets/summer.webp',
        CompanionPet.hamster => 'assets/pets/friends/hamster.webp',
        CompanionPet.robot => 'assets/pets/friends/robot.webp',
        CompanionPet.fox => 'assets/pets/friends/fox.webp',
        CompanionPet.teddy => 'assets/pets/friends/teddy.webp',
      };
}

Future<CompanionPet> loadCompanionPet(String childId) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'child_companion_$childId';
  final migration = 'child_companion_smiling_v2_$childId';
  if (!(prefs.getBool(migration) ?? false)) {
    await prefs.setString(key, CompanionPet.hamster.name);
    await prefs.setBool(migration, true);
  }
  final saved = prefs.getString(key);
  // The previous build shipped a corgi that did not match the cat animation.
  // Move that legacy choice to the polished hoodie cat instead of showing the
  // old dog after an upgrade.
  final migrated =
      saved == CompanionPet.corgi.name ? CompanionPet.cat.name : saved;
  if (migrated != saved) await prefs.setString(key, migrated!);
  return CompanionPet.values.where((pet) => pet.name == migrated).firstOrNull ??
      CompanionPet.hamster;
}
