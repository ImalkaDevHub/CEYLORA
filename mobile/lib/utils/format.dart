const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Trip dates are calendar dates stored as UTC midnight, so format the UTC
/// fields directly; converting to local time would shift the day.
String formatDate(DateTime d) {
  final u = d.toUtc();
  return '${u.day} ${_months[u.month - 1]} ${u.year}';
}

/// yyyy-MM-dd, the same shape an HTML date input sends to the API.
String toApiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "LKR 150,000" (decimals only when present).
String formatLkr(double amount) {
  final hasCents = amount != amount.roundToDouble();
  final fixed = amount.toStringAsFixed(hasCents ? 2 : 0);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return 'LKR ${parts.length > 1 ? '$whole.${parts[1]}' : whole}';
}
