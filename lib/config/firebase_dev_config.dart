/// Build-time switch for the free local Firebase Emulator Suite.
///
/// Production builds keep this disabled. For a phone connected over USB, use
/// `adb reverse` and pass `FIREBASE_EMULATOR_HOST=127.0.0.2`. For an Android
/// Studio emulator, use `10.0.2.2` instead.
abstract final class FirebaseDevConfig {
  static const useEmulator = bool.fromEnvironment(
    'USE_FIREBASE_EMULATOR',
    defaultValue: false,
  );
  static const host = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.2',
  );

  static const authPort = 9099;
  static const firestorePort = 8080;
  static const functionsPort = 5001;
}
