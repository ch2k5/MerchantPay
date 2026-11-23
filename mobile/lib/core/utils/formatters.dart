class Formatters {
  static String formatDzd(dynamic amount) {
    if (amount == null) return '0,00 DZD';
    double val = 0.0;
    if (amount is num) {
      val = amount.toDouble();
    } else if (amount is String) {
      val = double.tryParse(amount) ?? 0.0;
    }
    final isNeg = val < 0;
    val = val.abs();
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];

    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    final formattedInt = intPart.replaceAllMapped(reg, (match) => ' ');
    return '${isNeg ? '-' : ''}$formattedInt,$decPart DZD';
  }

  static String formatPct(dynamic pct) {
    if (pct == null) return '0,0 %';
    double val = (pct is num) ? pct.toDouble() : (double.tryParse(pct.toString()) ?? 0.0);
    return '${val.toStringAsFixed(1).replaceAll('.', ',')} %';
  }

  static String formatDate(dynamic date) {
    if (date == null) return '-';
    DateTime? dt;
    if (date is DateTime) {
      dt = date.toLocal();
    } else {
      dt = DateTime.tryParse(date.toString())?.toLocal();
    }
    if (dt == null) return date.toString();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  static String formatDateTime(dynamic date) {
    if (date == null) return '-';
    DateTime? dt;
    if (date is DateTime) {
      dt = date.toLocal();
    } else {
      dt = DateTime.tryParse(date.toString())?.toLocal();
    }
    if (dt == null) return date.toString();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }
}

// Top-level shortcuts for convenience
String formatDzd(dynamic amount) => Formatters.formatDzd(amount);
String formatPct(dynamic pct) => Formatters.formatPct(pct);
String formatDate(dynamic date) => Formatters.formatDate(date);
String formatDateTime(dynamic date) => Formatters.formatDateTime(date);
