import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/zone.dart';
import 'auth_service.dart';
import 'game_functions_service.dart';
import 'hex_grid_service.dart';

class ZoneRepository {
  static final _db = FirebaseFirestore.instance;
  static const _hexService = HexGridService();
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('zones');

  static DateTime? _date(dynamic value) =>
      value is Timestamp ? value.toDate() : null;

  static Zone _apply(Zone skeleton, Map<String, dynamic> data) {
    return skeleton.copyWith(
      ownerId: data['ownerId'] as String?,
      ownerName: data['ownerName'] as String?,
      ownerColor: data['colorHex'] != null
          ? AuthService.colorFromHex(data['colorHex'] as String)
          : null,
      upgradeLevel: (data['upgradeLevel'] as num?)?.toInt() ?? 0,
      baseRent: (data['baseRentSec'] as num?)?.toInt() ?? skeleton.baseRent,
      upgradeReadyAt: _date(data['upgradeReadyAt']),
      constructionStartedAt: _date(data['constructionStartedAt']),
      constructionFromLevel: (data['constructionFromLevel'] as num?)?.toInt(),
      siegeAttackerId: data['siegeAttackerId'] as String?,
      siegeProgressSec: (data['siegeProgressSec'] as num?)?.toInt() ?? 0,
      siegeRequiredSec: (data['siegeRequiredSec'] as num?)?.toInt() ?? 0,
      lastOwnerPresenceAt: _date(data['lastOwnerPresenceAt']),
    );
  }

  static Stream<List<Zone>> zonesAroundStream(LatLng location) {
    final localZones = _hexService.generateZones(location);
    final ids = localZones.map((z) => z.id).toList();
    return _col.where(FieldPath.documentId, whereIn: ids).snapshots().map((
      snap,
    ) {
      final firestoreMap = {for (final doc in snap.docs) doc.id: doc.data()};
      return localZones.map((zone) {
        final data = firestoreMap[zone.id];
        return data == null ? zone : _apply(zone, data);
      }).toList();
    });
  }

  static Future<Zone> loadZone(Zone skeleton) async {
    final snap = await _col.doc(skeleton.id).get();
    final data = snap.data();
    return data == null ? skeleton : _apply(skeleton, data);
  }

  /// Server validates the GPS point, 30-second capture, time credits, rent and
  /// inactive-owner siege in one transaction.
  static Future<Map<String, dynamic>> recordPresence({
    required String zoneId,
    required LatLng location,
    required double accuracy,
  }) {
    return GameFunctionsService.call('recordPresence', {
      'zoneId': zoneId,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'accuracy': accuracy,
    });
  }

  static Future<Map<String, dynamic>> upgradeZone(String zoneId, int newLevel) {
    return GameFunctionsService.call('startUpgrade', {
      'zoneId': zoneId,
      'toLevel': newLevel,
    });
  }
}
