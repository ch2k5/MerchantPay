import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pay/core/widgets/kpi_card.dart';

void main() {
  testWidgets('KpiCard renders title, value and delta chip correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KpiCard(
            title: 'Chiffre d\'Affaires',
            value: '48 000,00 DZD',
            deltaPct: 15.5,
            icon: Icons.payments,
          ),
        ),
      ),
    );

    expect(find.text('Chiffre d\'Affaires'), findsOneWidget);
    expect(find.text('48 000,00 DZD'), findsOneWidget);
    expect(find.text('+15,5 %'), findsOneWidget);
    expect(find.text('vs préc.'), findsOneWidget);
  });

  testWidgets('KpiCard renders negative delta with red badge', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KpiCard(
            title: 'Rejets',
            value: '12',
            deltaPct: -8.2,
            icon: Icons.close,
          ),
        ),
      ),
    );

    expect(find.text('Rejets'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('-8,2 %'), findsOneWidget);
  });

  testWidgets('KpiCard renders subtitle when deltaPct is null', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KpiCard(
            title: 'Transactions',
            value: '120',
            subtitle: 'Sur les 30 derniers jours',
            icon: Icons.receipt,
          ),
        ),
      ),
    );

    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Sur les 30 derniers jours'), findsOneWidget);
  });
}
