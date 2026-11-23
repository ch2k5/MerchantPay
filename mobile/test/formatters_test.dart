import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pay/core/utils/formatters.dart';

void main() {
  group('Formatters Tests', () {
    test('formatDzd formats numbers according to fr_FR currency convention', () {
      expect(formatDzd(0), '0,00 DZD');
      expect(formatDzd(48000), contains('48'));
      expect(formatDzd(48000), contains('000,00'));
      expect(formatDzd(48000), contains('DZD'));
      expect(formatDzd(1250.5), contains('1'));
      expect(formatDzd(1250.5), contains('250,50'));
    });

    test('formatDzd handles string numbers and nulls safely', () {
      expect(formatDzd(null), '0,00 DZD');
      expect(formatDzd('1500'), contains('1'));
      expect(formatDzd('1500'), contains('500,00'));
      expect(formatDzd('invalid'), '0,00 DZD');
    });

    test('formatPct formats percentages with comma decimal', () {
      expect(formatPct(0), '0,0 %');
      expect(formatPct(15.2), '15,2 %');
      expect(formatPct(-8.75), '-8,8 %');
      expect(formatPct(null), '0,0 %');
    });

    test('formatDate handles DateTime and ISO strings', () {
      final dt = DateTime(2026, 11, 23);
      expect(formatDate(dt), '23/11/2026');
      expect(formatDate('2026-11-23T14:30:00Z'), contains('23/11/2026'));
      expect(formatDate(null), '-');
    });

    test('formatDateTime formats date and time in 24h format', () {
      final dt = DateTime(2026, 11, 23, 14, 30);
      expect(formatDateTime(dt), '23/11/2026 14:30');
      expect(formatDateTime(null), '-');
    });
  });
}
