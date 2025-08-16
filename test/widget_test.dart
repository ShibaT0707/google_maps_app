// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_app/main.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  testWidgets('MapScreen builds and displays map', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Allow the widget to render.
    await tester.pumpAndSettle();

    // Verify that the GoogleMap widget is present.
    expect(find.byType(GoogleMap), findsOneWidget);

    // Verify that the floating action button for location is present.
    expect(find.byIcon(Icons.my_location), findsOneWidget);

    // Verify that the initial listening status icon is present.
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}
