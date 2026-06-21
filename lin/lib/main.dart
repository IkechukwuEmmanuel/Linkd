import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_constants.dart';
import 'core/utils/service_locator.dart';
import 'core/utils/logger.dart';
import 'linkd_app.dart';
import 'presentation/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (messaging/analytics only; auth is via Supabase).
  try {
    await Firebase.initializeApp();
    AppLogger.info('Firebase initialized successfully');
  } catch (e) {
    AppLogger.error('Firebase initialization error', e);
  }

  // Initialize Supabase Auth when configured via --dart-define.
  if (AppConstants.useSupabaseAuth) {
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        // anonKey still works; SDK renamed it to publishableKey in a later
        // version. The anon/publishable key value is the same.
        // ignore: deprecated_member_use
        anonKey: AppConstants.supabaseAnonKey,
      );
      AppLogger.info('Supabase initialized successfully');
    } catch (e) {
      AppLogger.error('Supabase initialization error', e);
    }
  }

  // Setup service locator and dependencies
  await setupServiceLocator();

  // Initialize SharedPreferences for Riverpod
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const LinkdApp(),
    ),
  );
}
