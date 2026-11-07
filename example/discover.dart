// Lists the renderers (and webOS TVs) on the LAN for 8 seconds:
//   dart run example/discover.dart
import 'dart:async';

import 'package:dlna_dart/dlna_dart.dart';

Future<void> main() async {
  final described = <Uri>{};
  final sub = SsdpSearch.search([SsdpTarget.mediaRenderer, SsdpTarget.webOsSecondScreen]).listen((r) async {
    if (r.st == SsdpTarget.webOsSecondScreen) print('webOS second screen: ${r.address.address} (${r.server})');
    if (!described.add(r.location)) return;
    try {
      for (final d in await UpnpDevice.fetch(r.location)) {
        final renderer = DlnaRenderer.of(d);
        if (renderer != null) print('renderer: ${renderer.name} [${d.manufacturer} ${d.modelName}] ${d.udn} at ${r.location}');
      }
    } on Exception catch (e) {
      print('${r.location}: $e');
    }
  });
  await Future<void>.delayed(const Duration(seconds: 8));
  await sub.cancel();
}
