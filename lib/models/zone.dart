import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// The resource is measured in seconds. The UI presents it as minutes/hours.
const List<String> kUpgradeNames = [
  'Arsa',
  'Çadır',
  'Ev',
  'Apartman',
  'Otel',
  'Gökdelen',
];
const List<int> kRentSeconds = [0, 60, 5 * 60, 20 * 60, 60 * 60, 3 * 60 * 60];
const List<int> kUpgradeCostsSeconds = [
  0,
  5 * 60,
  30 * 60,
  2 * 60 * 60,
  8 * 60 * 60,
  24 * 60 * 60,
];
const List<int> kUpgradeBuildSeconds = [
  0,
  5 * 60,
  30 * 60,
  2 * 60 * 60,
  8 * 60 * 60,
  24 * 60 * 60,
];
const List<int> kSiegeSeconds = [
  10 * 60,
  10 * 60,
  30 * 60,
  2 * 60 * 60,
  6 * 60 * 60,
  24 * 60 * 60,
];

class Zone {
  const Zone({
    required this.id,
    required this.q,
    required this.r,
    required this.center,
    required this.boundary,
    this.ownerId,
    this.ownerName,
    this.ownerColor,
    this.upgradeLevel = 0,
    this.poiName,
    this.baseRent = 10,
    this.upgradeReadyAt,
    this.constructionStartedAt,
    this.constructionFromLevel,
    this.siegeAttackerId,
    this.siegeProgressSec = 0,
    this.siegeRequiredSec = 0,
    this.lastOwnerPresenceAt,
  });

  final String id;
  final int q;
  final int r;
  final LatLng center;
  final List<LatLng> boundary;
  final String? ownerId;
  final String? ownerName;
  final Color? ownerColor;
  final int upgradeLevel;
  final String? poiName;
  final int baseRent;
  final DateTime? upgradeReadyAt;
  final DateTime? constructionStartedAt;
  final int? constructionFromLevel;
  final String? siegeAttackerId;
  final int siegeProgressSec;
  final int siegeRequiredSec;
  final DateTime? lastOwnerPresenceAt;

  bool get isOwned => ownerId != null;
  bool get isUnderConstruction =>
      upgradeReadyAt != null && upgradeReadyAt!.isAfter(DateTime.now());

  /// The structure that should be rendered while a new level is being built.
  /// The server stores the target level immediately, but the map should keep
  /// showing the previous structure until [upgradeReadyAt].
  int get visualUpgradeLevel => isUnderConstruction
      ? (constructionFromLevel ?? (upgradeLevel - 1)).clamp(0, 5)
      : upgradeLevel.clamp(0, 5);
  int get rentSeconds => kRentSeconds[visualUpgradeLevel];
  double get rentPerMinute => rentSeconds / 60.0;
  int get nextLevel =>
      upgradeLevel < kUpgradeNames.length - 1 ? upgradeLevel + 1 : upgradeLevel;

  String get rentLabel {
    if (rentSeconds < 60) return '$rentSeconds sn';
    if (rentSeconds % 3600 == 0) return '${rentSeconds ~/ 3600} sa';
    return '${rentSeconds ~/ 60} dk';
  }

  Color get fillColor => isOwned
      ? (ownerColor ?? const Color(0xFF3C7650)).withValues(alpha: 0.45)
      : const Color(0x1497B873);

  Color get borderColor => isOwned
      ? (ownerColor ?? const Color(0xFF3C7650)).withValues(alpha: 0.9)
      : const Color(0x90697651);

  Zone copyWith({
    String? ownerId,
    String? ownerName,
    Color? ownerColor,
    int? upgradeLevel,
    String? poiName,
    int? baseRent,
    DateTime? upgradeReadyAt,
    DateTime? constructionStartedAt,
    int? constructionFromLevel,
    String? siegeAttackerId,
    int? siegeProgressSec,
    int? siegeRequiredSec,
    DateTime? lastOwnerPresenceAt,
  }) {
    return Zone(
      id: id,
      q: q,
      r: r,
      center: center,
      boundary: boundary,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      ownerColor: ownerColor ?? this.ownerColor,
      upgradeLevel: upgradeLevel ?? this.upgradeLevel,
      poiName: poiName ?? this.poiName,
      baseRent: baseRent ?? this.baseRent,
      upgradeReadyAt: upgradeReadyAt ?? this.upgradeReadyAt,
      constructionStartedAt:
          constructionStartedAt ?? this.constructionStartedAt,
      constructionFromLevel:
          constructionFromLevel ?? this.constructionFromLevel,
      siegeAttackerId: siegeAttackerId ?? this.siegeAttackerId,
      siegeProgressSec: siegeProgressSec ?? this.siegeProgressSec,
      siegeRequiredSec: siegeRequiredSec ?? this.siegeRequiredSec,
      lastOwnerPresenceAt: lastOwnerPresenceAt ?? this.lastOwnerPresenceAt,
    );
  }
}
