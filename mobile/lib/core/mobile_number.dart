/// The clinician's own mobile number, in the server's form: `+<country code><number>`.
/// Indian numbers may be typed without the code. Mirrors `normalize_mobile` in app/main.py;
/// the server checks it again.
library;

final _separators = RegExp(r'[\s().-]');
final _indianLocal = RegExp(r'^0?[6-9]\d{9}$');
final _indianNoPlus = RegExp(r'^91[6-9]\d{9}$');
final _indian = RegExp(r'^\+91[6-9]\d{9}$');
final _international = RegExp(r'^\+[1-9]\d{7,14}$');

/// The number as +919876543210, or null if it isn't a mobile number.
String? normalizeMobile(String raw) {
  var v = raw.replaceAll(_separators, '');
  if (v.startsWith('00')) v = '+${v.substring(2)}';
  if (_indianLocal.hasMatch(v)) {
    v = '+91${v.substring(v.length - 10)}';
  } else if (_indianNoPlus.hasMatch(v)) {
    v = '+$v';
  }
  final ok = v.startsWith('+91') ? _indian.hasMatch(v) : _international.hasMatch(v);
  return ok ? v : null;
}
