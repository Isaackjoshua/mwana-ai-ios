import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mwana_ai/screens/input_selection_screen.dart';

void main() {
  testWidgets('InputSelectionScreen shows all 3 input options', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InputSelectionScreen()),
    );
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
  });
}
