// Basic Flutter widget test for M5ToughTool

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:m5_mac/main.dart';
import 'package:m5_mac/services/esp_service.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EspService(),
        child: const MainApp(),
      ),
    );

    // Verify that the app title is shown
    expect(find.text('M5Stack Tough Kommunikationstool'), findsOneWidget);

    // Verify navigation rail has tabs
    expect(find.text('Importieren'), findsOneWidget);
    expect(find.text('Konfiguration'), findsOneWidget);
    expect(find.text('Speicher'), findsOneWidget);
  });
}
