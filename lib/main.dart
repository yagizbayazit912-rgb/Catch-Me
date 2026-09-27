import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'config/firebase_dev_config.dart';
import 'screens/map_screen.dart';
import 'services/auth_service.dart';
import 'services/game_functions_service.dart';
import 'theme/kingdom_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (FirebaseDevConfig.useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(
      FirebaseDevConfig.host,
      FirebaseDevConfig.authPort,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      FirebaseDevConfig.host,
      FirebaseDevConfig.firestorePort,
    );
    GameFunctionsService.useEmulator(
      FirebaseDevConfig.host,
      FirebaseDevConfig.functionsPort,
    );
  }
  await AuthService.signInAnonymously();
  runApp(const CatchMeApp());
}

class CatchMeApp extends StatelessWidget {
  const CatchMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Catch Me',
      debugShowCheckedModeBanner: false,
      theme: KingdomTheme.data,
      home: const MapScreen(),
    );
  }
}
