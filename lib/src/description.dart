import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

/// One service of a UPnP device, with its URLs already absolute.
class UpnpService {
  const UpnpService({required this.serviceType, required this.serviceId, required this.controlUrl, this.eventSubUrl, this.scpdUrl});

  /// e.g. `urn:schemas-upnp-org:service:AVTransport:1`.
  final String serviceType;
  final String serviceId;
  final Uri controlUrl;
  final Uri? eventSubUrl;
  final Uri? scpdUrl;
}

/// A device from a description document (the root device or an embedded
/// one: some renderers put the MediaRenderer inside a root "Basic" device).
class UpnpDevice {
  const UpnpDevice({
    required this.location,
    required this.udn,
    required this.deviceType,
    required this.friendlyName,
    this.manufacturer,
    this.modelName,
    this.services = const [],
  });

  /// Where the description was read (the SSDP `LOCATION`).
  final Uri location;

  /// Unique device name (`uuid:…`): stable across restarts and IP changes.
  final String udn;
  final String deviceType;
  final String friendlyName;
  final String? manufacturer;
  final String? modelName;
  final List<UpnpService> services;

  bool get isMediaRenderer => deviceType.contains(':device:MediaRenderer:');

  /// The first service whose type starts with [typePrefix] (version-agnostic:
  /// `urn:schemas-upnp-org:service:AVTransport:`).
  UpnpService? service(String typePrefix) {
    for (final s in services) {
      if (s.serviceType.startsWith(typePrefix)) return s;
    }
    return null;
  }

  /// Every device in a description document, root first. Relative URLs are
  /// resolved against `URLBase` (UPnP 1.0) or else [location] (1.1 dropped
  /// `URLBase`).
  static List<UpnpDevice> parseAll(String xml, Uri location) {
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;
    final urlBase = _text(root, 'URLBase');
    final base = urlBase == null ? location : (Uri.tryParse(urlBase) ?? location);
    final devices = <UpnpDevice>[];
    for (final d in root.descendantElements.where((e) => e.name.local == 'device')) {
      final services = <UpnpService>[];
      // Only this device's own services, not its embedded devices'.
      final list = d.childElements.where((e) => e.name.local == 'serviceList').firstOrNull;
      for (final s in list?.childElements.where((e) => e.name.local == 'service') ?? const <XmlElement>[]) {
        final type = _text(s, 'serviceType');
        final control = _text(s, 'controlURL');
        if (type == null || control == null) continue;
        Uri? resolve(String? url) => url == null ? null : base.resolve(url);
        services.add(UpnpService(
          serviceType: type,
          serviceId: _text(s, 'serviceId') ?? type,
          controlUrl: base.resolve(control),
          eventSubUrl: resolve(_text(s, 'eventSubURL')),
          scpdUrl: resolve(_text(s, 'SCPDURL')),
        ));
      }
      devices.add(UpnpDevice(
        location: location,
        udn: _text(d, 'UDN') ?? location.toString(),
        deviceType: _text(d, 'deviceType') ?? '',
        friendlyName: _text(d, 'friendlyName') ?? location.host,
        manufacturer: _text(d, 'manufacturer'),
        modelName: _text(d, 'modelName'),
        services: services,
      ));
    }
    return devices;
  }

  /// Downloads and parses the description at [location].
  static Future<List<UpnpDevice>> fetch(Uri location, {HttpClient? http, Duration timeout = const Duration(seconds: 5)}) async {
    final client = http ?? HttpClient();
    try {
      final request = await client.getUrl(location).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: location);
      }
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      return parseAll(body, location);
    } finally {
      if (http == null) client.close(force: true);
    }
  }
}

/// The text of [parent]'s direct child named [local] (any namespace).
String? _text(XmlElement parent, String local) {
  for (final e in parent.childElements) {
    if (e.name.local == local) {
      final t = e.innerText.trim();
      return t.isEmpty ? null : t;
    }
  }
  return null;
}
