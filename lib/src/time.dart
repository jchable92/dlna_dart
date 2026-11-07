/// UPnP AV time values ("H+:MM:SS[.F+]" or "H+:MM:SS[.F0/F1]").
///
/// Renderers answer `NOT_IMPLEMENTED`, an empty string or `0:00:00` when they
/// don't know: the first two parse to null.
Duration? parseUpnpTime(String? text) {
  if (text == null) return null;
  final m = _time.firstMatch(text.trim());
  if (m == null) return null;
  var millis = 0;
  final fraction = m[4];
  if (fraction != null) {
    final denominator = m[5];
    if (denominator != null) {
      final d = int.parse(denominator);
      millis = d == 0 ? 0 : (int.parse(fraction) * 1000 / d).round();
    } else {
      // A decimal fraction: "1.5" is 500 ms, "1.05" is 50 ms.
      millis = int.parse(fraction.padRight(3, '0').substring(0, 3));
    }
  }
  return Duration(hours: int.parse(m[1]!), minutes: int.parse(m[2]!), seconds: int.parse(m[3]!), milliseconds: millis);
}

final _time = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+)(?:/(\d+))?)?$');

/// "HH:MM:SS" (what every renderer accepts as a `REL_TIME` seek target), or
/// "HH:MM:SS.mmm" with [millis] (DIDL-Lite `res@duration`).
String formatUpnpTime(Duration d, {bool millis = false}) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final base = '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  return millis ? '$base.${d.inMilliseconds.remainder(1000).toString().padLeft(3, '0')}' : base;
}
