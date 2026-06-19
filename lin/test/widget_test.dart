// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:linkd_app/linkd_app.dart';
import 'package:linkd_app/presentation/providers/auth_provider.dart';

void main() {
  testWidgets('App can be built', (WidgetTester tester) async {
    // sharedPreferencesProvider intentionally throws unless overridden, so
    // provide a mock instance (the app is normally initialized in main()).
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const LinkdApp(),
      ),
    );
    await tester.pump();

    // Verify the app builds and renders a MaterialApp without errors.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
