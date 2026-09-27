import 'package:catch_me/models/zone.dart';
import 'package:catch_me/services/hex_grid_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unfinished house shows tent and charges tent rent', () {
    final zone = const HexGridService()
        .zoneAt(0, 0)
        .copyWith(
          ownerId: 'owner',
          upgradeLevel: 2,
          constructionFromLevel: 1,
          upgradeReadyAt: DateTime.now().add(const Duration(minutes: 10)),
        );
    expect(zone.visualUpgradeLevel, 1);
    expect(zone.rentSeconds, kRentSeconds[1]);
    expect(zone.isUnderConstruction, isTrue);
  });
  test('finished house shows house and charges house rent', () {
    final zone = const HexGridService()
        .zoneAt(0, 0)
        .copyWith(
          ownerId: 'owner',
          upgradeLevel: 2,
          constructionFromLevel: 1,
          upgradeReadyAt: DateTime.now().subtract(const Duration(seconds: 1)),
        );
    expect(zone.visualUpgradeLevel, 2);
    expect(zone.rentSeconds, kRentSeconds[2]);
    expect(zone.isUnderConstruction, isFalse);
  });
  test('first tent and legacy pending upgrade use previous level', () {
    final zone = const HexGridService()
        .zoneAt(0, 0)
        .copyWith(
          ownerId: 'owner',
          upgradeLevel: 1,
          upgradeReadyAt: DateTime.now().add(const Duration(minutes: 1)),
        );
    expect(zone.visualUpgradeLevel, 0);
    expect(zone.rentSeconds, 0);
  });
}
