# dlna_dart

Pure-Dart DLNA / UPnP AV client (no Flutter): find renderers on the LAN,
read their descriptions and control playback.

```dart
import 'package:dlna_dart/dlna_dart.dart';

final sub = SsdpSearch.search([SsdpTarget.mediaRenderer]).listen((r) async {
  for (final device in await UpnpDevice.fetch(r.location)) {
    final tv = DlnaRenderer.of(device);
    if (tv == null) continue;
    await tv.setUri(url, metadata: DidlItem(title: 'Movie', url: url, mimeType: 'video/mp4'));
    await tv.play();
  }
});
// … later
await sub.cancel();
```

- `SsdpSearch.search` sends M-SEARCH from an ephemeral port and reads the
  unicast replies (no port-1900 bind, no Android multicast lock). Pass the
  Wi-Fi address as `bindAddress` on phones so the search doesn't leave
  through mobile data.
- `UpnpDevice.parseAll` returns the root and embedded devices with absolute
  service URLs (`URLBase` or the description's location).
- `DlnaRenderer`: `setUri`, `play`, `pause`, `stop`, `seek`,
  `transportInfo`, `positionInfo`, `mediaInfo`, volume and mute. Failures
  are `UpnpException`s with the renderer's UPnP error code.
- `DidlItem` builds the `CurrentURIMetaData` (title, DLNA range-seek flags,
  duration, Samsung-style external subtitles).

`dart run example/discover.dart` lists what answers on your network.
