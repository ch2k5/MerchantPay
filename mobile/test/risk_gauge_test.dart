import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pay/core/widgets/risk_gauge.dart';

void main() {
  testWidgets('RiskGauge displays high score and Élevé label', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RiskGauge(score: 85),
        ),
      ),
    );

    expect(find.text('85'), findsOneWidget);
    expect(find.text('Élevé'), findsOneWidget);
  });

  testWidgets('RiskGauge displays low score and Faible label', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RiskGauge(score: 25),
        ),
      ),
    );

    expect(find.text('25'), findsOneWidget);
    expect(find.text('Faible'), findsOneWidget);
  });

  testWidgets('RiskGauge displays moderate score and Modéré label', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RiskGauge(score: 55),
        ),
      ),
    );

    expect(find.text('55'), findsOneWidget);
    expect(find.text('Modéré'), findsOneWidget);
  });
}
