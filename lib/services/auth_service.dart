import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'game_functions_service.dart';

/// Anonymous Firebase session and the read-only user profile stream.
class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static String? get uid => _auth.currentUser?.uid;
  static String? startupWarning;

  static Future<User> signInAnonymously() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    // Profile creation/migration is an Admin transaction. This keeps the
    // client from minting time or changing its own ownership counters.
    try {
      await GameFunctionsService.call('ensureProfile', {
        'displayName': 'Gezgin ${user.uid.substring(0, 4).toUpperCase()}',
      }).timeout(const Duration(seconds: 8));
      startupWarning = null;
    } catch (error) {
      // The map can still open while the local Functions emulator reconnects.
      // State-changing actions remain server-authoritative and retry later.
      startupWarning = 'Sunucu bağlantısı bekleniyor.';
      debugPrint('ensureProfile bağlantısı bekleniyor: $error');
    }
    return user;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _db.collection('users').doc(id).snapshots();
  }

  static int timeBalanceSeconds(Map<String, dynamic> profile) =>
      (profile['timeBalanceSec'] as num?)?.toInt() ??
      ((profile['points'] as num?)?.toInt() ?? 0) * 60;

  static String formatTime(int seconds) {
    final safe = seconds.clamp(0, 999999999);
    if (safe >= 3600) {
      final hours = safe ~/ 3600;
      final minutes = (safe % 3600) ~/ 60;
      return minutes == 0 ? '${hours}sa' : '${hours}sa ${minutes}dk';
    }
    return '${safe ~/ 60}dk';
  }

  static Color colorFromHex(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}
