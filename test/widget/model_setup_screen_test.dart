import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mwana_ai/screens/model_setup_screen.dart';

void main() {
  testWidgets('ModelSetupScreen shows From Device and Download URL tabs', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ModelSetupScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('From Device'), findsOneWidget);
    expect(find.text('Download URL'), findsOneWidget);
    expect(find.text('Pick Model File'), findsOneWidget);
  });

  testWidgets('URL tab shows url and token fields', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ModelSetupScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download URL'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Model URL'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'HuggingFace Token (optional)'), findsOneWidget);
    expect(find.text('Download & Install'), findsOneWidget);
  });
}
