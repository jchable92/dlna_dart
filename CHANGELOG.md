## 0.1.1
- `SsdpSearch.search` also listens for `NOTIFY ssdp:alive` on port 1900 (as 0.0.x did), so devices that only announce themselves are found too. Port 1900 shared when possible (`reusePort` falls back on Android).

## 0.1.0
- Rewritten for Dart 3 (breaking): `SsdpSearch`, `UpnpDevice`, `DlnaRenderer`, `DidlItem`, `SoapClient`.
- Discovery reads every reply (the old loop read one datagram every 2–3 s) and no longer binds port 1900.
- Service URLs resolved properly (relative to `URLBase` or the location; absolute ones kept); embedded devices found.
- SOAP bodies built with the XML builder (URLs with `&`, titles with `<` are escaped); faults carry the UPnP error code.
- Fixed fractional times (`0:00:01.5` was 5 ms) and DIDL `res@duration` (was ISO 8601).
- No more `print`s. Tests.

## [0.0.8] - add play type param in set play url
## [0.0.7] - add title param in set play url
## [0.0.6] - enhance class name , add more dlna method
## [0.0.5] - update dependencies
## [0.0.4] - fix ios joinMulticast error.
## [0.0.3] - use xml 5.1.2.
## [0.0.2] - support reusePort option.
## [0.0.1] - init dlna-dart.
