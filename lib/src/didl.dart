import 'package:xml/xml.dart';

import 'time.dart';

/// What `SetAVTransportURI` sends as `CurrentURIMetaData`: the title the TV
/// shows and the resource it should open.
class DidlItem {
  const DidlItem({
    required this.title,
    required this.url,
    this.mimeType = 'video/mp4',
    this.upnpClass = videoItem,
    this.duration,
    this.size,
    this.albumArtUrl,
    this.subtitleUrl,
    this.subtitleType = 'srt',
    this.seekable = true,
  });

  static const videoItem = 'object.item.videoItem';
  static const audioItem = 'object.item.audioItem';

  final String title;
  final String url;

  /// The resource's type; TVs refuse what they think they can't play, so
  /// it should match what the server sends (`video/mp4`, `video/x-matroska`,
  /// `application/vnd.apple.mpegurl`…).
  final String mimeType;
  final String upnpClass;
  final Duration? duration;
  final int? size;
  final String? albumArtUrl;

  /// External subtitles, announced the Samsung way (`sec:CaptionInfoEx`) and
  /// as a second `res` (others); renderers that know neither ignore them.
  final String? subtitleUrl;
  final String subtitleType;

  /// Whether the server honours byte ranges (DLNA.ORG_OP=01): without it
  /// most TVs disable seeking.
  final bool seekable;

  /// `http-get:*:<mime>:<DLNA flags>`: streaming transfer mode + range seek,
  /// what local media servers announce.
  String get protocolInfo =>
      'http-get:*:$mimeType:DLNA.ORG_OP=${seekable ? '01' : '00'};DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000';

  String toXml() {
    final b = XmlBuilder();
    b.element('DIDL-Lite', attributes: {
      'xmlns': 'urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/',
      'xmlns:dc': 'http://purl.org/dc/elements/1.1/',
      'xmlns:upnp': 'urn:schemas-upnp-org:metadata-1-0/upnp/',
      'xmlns:dlna': 'urn:schemas-dlna-org:metadata-1-0/',
      'xmlns:sec': 'http://www.sec.co.kr/',
    }, nest: () {
      b.element('item', attributes: {'id': '0', 'parentID': '-1', 'restricted': '1'}, nest: () {
        b.element('dc:title', nest: title);
        b.element('upnp:class', nest: upnpClass);
        if (albumArtUrl != null) b.element('upnp:albumArtURI', nest: albumArtUrl);
        final sub = subtitleUrl;
        if (sub != null) b.element('sec:CaptionInfoEx', attributes: {'sec:type': subtitleType}, nest: sub);
        b.element('res', attributes: {
          'protocolInfo': protocolInfo,
          if (duration != null) 'duration': formatUpnpTime(duration!, millis: true),
          if (size != null) 'size': '$size',
        }, nest: url);
        if (sub != null) b.element('res', attributes: {'protocolInfo': 'http-get:*:text/$subtitleType:*'}, nest: sub);
      });
    });
    return b.buildDocument().toXmlString();
  }
}
