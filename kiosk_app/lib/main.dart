import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/camera_screen.dart';
import 'services/error_logger.dart';
import 'services/ist_clock.dart';
import 'services/kiosk_backend.dart';
import 'services/local_database.dart';
import 'services/supabase_backend.dart';

Future<void> main() async {
  // Everything, including WidgetsFlutterBinding.ensureInitialized(), must
  // run inside the same zone as runApp() -- creating the binding outside
  // this zone and then calling runApp() inside it trips Flutter's
  // zone-mismatch assertion. runZonedGuarded is what catches any
  // asynchronous error (including ones during the startup sequence below)
  // that would otherwise vanish with nothing watching an unattended
  // kiosk's console.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    KioskConfig.assertConfigured();

    // FlutterError.onError covers errors the framework itself catches
    // (build/layout/paint) -- without this they only print to the console
    // and are otherwise invisible on a kiosk with none attached.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      ErrorLogger.log(
        details.exception,
        stackTrace: details.stack,
        context: 'FlutterError (${details.context?.toDescription() ?? 'unknown'})',
      );
    };

    // Belt-and-suspenders alongside runZonedGuarded: platform-dispatched
    // errors (e.g. from platform channel callbacks) don't always flow
    // through the zone's error handler.
    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorLogger.log(error, stackTrace: stack, context: 'PlatformDispatcher');
      return true;
    };

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    await LocalDatabase.instance.open();
    unawaited(_pruneOldAttendanceState());

    await Supabase.initialize(
      url: KioskConfig.supabaseUrl,
      publishableKey: KioskConfig.supabaseAnonKey,
    );

    // The only place a concrete backend is chosen -- everything else in the
    // app talks to KioskBackend.instance, so swapping Supabase for a
    // different backend later means writing a new KioskBackend
    // implementation and changing only this one line.
    KioskBackend.instance = SupabaseBackend();

    // Offline-first: a no-network sign-in failure at cold boot must not stop
    // the kiosk from starting. Supabase.initialize() above already restored
    // any session persisted from a previous successful sign-in, so the app
    // can still function (cached roster, offline queueing) until SyncService
    // manages to sign in for real. See SyncService._ensureSession for the
    // retry.
    try {
      await KioskBackend.instance.signInAsKiosk().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Kiosk sign-in failed at startup (continuing offline): $e');
    }

    runApp(const KioskApp());
  }, (error, stack) {
    ErrorLogger.log(error, stackTrace: stack, context: 'runZonedGuarded');
  });
}

Future<void> _pruneOldAttendanceState() async {
  try {
    await LocalDatabase.instance
        .pruneAttendanceStateBefore(IstClock.dateKeyDaysAgo(attendanceStateRetentionDays));
  } catch (e, st) {
    await ErrorLogger.log(e, stackTrace: st, context: 'pruneOldAttendanceState');
  }
}

class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const CameraScreen(),
    );
  }
}
