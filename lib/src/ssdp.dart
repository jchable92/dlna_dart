import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Search targets worth knowing.
abstract final class SsdpTarget {
  static const all = 'ssdp:all';
  static const mediaRenderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';
  static const avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';

  /// LG webOS TVs (their second-screen API, used to open the TV's browser).
  static const webOsSecondScreen = 'urn:lge-com:service:webos-second-screen:1';
}

/// One answer to an M-SEARCH (or a `NOTIFY ssdp:alive`).
class SsdpResponse {
  const SsdpResponse({required this.location, required this.st, required this.usn, required this.headers, required this.address});

  final Uri location;

  /// Search target (or the `NT` of a notify).
  final String st;
  final String usn;

  /// Every header, keys upper-cased.
  final Map<String, String> headers;

  /// Who answered.
  final InternetAddress address;

  String? get server => headers['SERVER'];

  /// The `uuid:…` part of [usn], shared by every service of one device.
  String get uuid => usn.split('::').first;

  /// Parses a datagram; null when it isn't a search response or an alive
  /// notify with a location (M-SEARCHes from other apps, byebyes…).
  static SsdpResponse? parse(String message, InternetAddress from) {
    final lines = const LineSplitter().convert(message);
    if (lines.isEmpty) return null;
    final start = lines.first.trim().toUpperCase();
    final isResponse = start.startsWith('HTTP/1.') && start.contains(' 200');
    final isNotify = start.startsWith('NOTIFY ');
    if (!isResponse && !isNotify) return null;
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      headers[line.substring(0, i).trim().toUpperCase()] = line.substring(i + 1).trim();
    }
    if (isNotify && headers['NTS']?.toLowerCase() != 'ssdp:alive') return null;
    final location = Uri.tryParse(headers['LOCATION'] ?? '');
    final st = headers[isResponse ? 'ST' : 'NT'];
    if (location == null || !location.hasScheme || st == null) return null;
    return SsdpResponse(location: location, st: st, usn: headers['USN'] ?? st, headers: headers, address: from);
  }
}

/// SSDP discovery over unicast replies: M-SEARCH goes to the multicast group
/// from an ephemeral port and devices answer that port directly, so no
/// multicast lock (Android) or port 1900 bind (often taken) is needed.
abstract final class SsdpSearch {
  static final group = InternetAddress('239.255.255.250');
  static const port = 1900;

  /// Searches for [targets] every [interval] (UDP drops packets; devices
  /// answer late) until the subscription is cancelled. Each (usn, st) is
  /// emitted once. [bindAddress]: the Wi-Fi address, so the search leaves
  /// through that interface and not mobile data.
  static Stream<SsdpResponse> search(
    List<String> targets, {
    InternetAddress? bindAddress,
    Duration interval = const Duration(seconds: 3),
    int mx = 2,
  }) {
    RawDatagramSocket? socket;
    Timer? timer;
    final seen = <String>{};
    late final StreamController<SsdpResponse> controller;

    void send() {
      final s = socket;
      if (s == null) return;
      for (final st in targets) {
        final msg = 'M-SEARCH * HTTP/1.1\r\n'
            'HOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: $mx\r\n'
            'ST: $st\r\n'
            '\r\n';
        try {
          s.send(utf8.encode(msg), group, port);
        } on SocketException {
          // No route right now (Wi-Fi off): the next round retries.
        }
      }
    }

    controller = StreamController<SsdpResponse>(
      onListen: () async {
        try {
          final s = socket = await RawDatagramSocket.bind(bindAddress ?? InternetAddress.anyIPv4, 0);
          s.multicastHops = 4;
          s.listen((event) {
            if (event != RawSocketEvent.read) return;
            // Drain every datagram that arrived, not only the first.
            for (var d = s.receive(); d != null; d = s.receive()) {
              final r = SsdpResponse.parse(utf8.decode(d.data, allowMalformed: true), d.address);
              if (r != null && seen.add('${r.usn}|${r.st}') && !controller.isClosed) controller.add(r);
            }
          });
          send();
          timer = Timer.periodic(interval, (_) => send());
        } on SocketException catch (e, st) {
          controller.addError(e, st);
          await controller.close();
        }
      },
      onCancel: () {
        timer?.cancel();
        socket?.close();
        socket = null;
      },
    );
    return controller.stream;
  }
}
