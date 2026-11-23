import 'package:flutter_test/flutter_test.dart';
import 'formatters_test.dart' as formatters_test;
import 'kpi_card_test.dart' as kpi_card_test;
import 'risk_gauge_test.dart' as risk_gauge_test;

void main() {
  group('Merchant Pay Test Suite', () {
    formatters_test.main();
    kpi_card_test.main();
    risk_gauge_test.main();
  });
}
