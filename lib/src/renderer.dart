import 'package:xml/xml.dart';

import 'description.dart';
import 'didl.dart';
import 'soap.dart';
import 'time.dart';

enum TransportState { stopped, playing, paused, transitioning, noMedia, unknown }

TransportState _state(String? s) => switch (s) {
      'STOPPED' => TransportState.stopped,
      'PLAYING' => TransportState.playing,
      'PAUSED_PLAYBACK' => TransportState.paused,
      'TRANSITIONING' => TransportState.transitioning,
      'NO_MEDIA_PRESENT' => TransportState.noMedia,
      _ => TransportState.unknown,
    };

class TransportInfo {
  const TransportInfo({required this.state, this.status, this.speed});

  final TransportState state;

  /// `OK` or `ERROR_OCCURRED` (the TV gave up on the stream).
  final String? status;
  final String? speed;

  bool get failed => status == 'ERROR_OCCURRED';
}

class PositionInfo {
  const PositionInfo({this.trackDuration, this.relTime, this.trackUri});

  /// Null while the renderer doesn't know it yet.
  final Duration? trackDuration;
  final Duration? relTime;
  final String? trackUri;
}

class MediaInfo {
  const MediaInfo({this.mediaDuration, this.currentUri});
  final Duration? mediaDuration;
  final String? currentUri;
}

/// Controls one MediaRenderer through its AVTransport (and, when present,
/// RenderingControl) service.
class DlnaRenderer {
  DlnaRenderer._(this.device, this._transport, this._rendering, this._soap);

  /// Null when [device] has no AVTransport service.
  static DlnaRenderer? of(UpnpDevice device, {SoapClient? soap}) {
    final transport = device.service('urn:schemas-upnp-org:service:AVTransport:');
    if (transport == null) return null;
    return DlnaRenderer._(device, transport, device.service('urn:schemas-upnp-org:service:RenderingControl:'), soap ?? SoapClient());
  }

  final UpnpDevice device;
  final UpnpService _transport;
  final UpnpService? _rendering;
  final SoapClient _soap;

  String get id => device.udn;
  String get name => device.friendlyName;
  bool get hasVolume => _rendering != null;

  Future<XmlElement> _av(String action, [Map<String, String> args = const {}]) =>
      _soap.call(_transport.controlUrl, _transport.serviceType, action, {'InstanceID': '0', ...args});

  Future<XmlElement> _rc(String action, [Map<String, String> args = const {}]) {
    final rc = _rendering;
    if (rc == null) throw UpnpException(action, 'no RenderingControl service');
    return _soap.call(rc.controlUrl, rc.serviceType, action, {'InstanceID': '0', 'Channel': 'Master', ...args});
  }

  Future<void> setUri(String url, {DidlItem? metadata}) =>
      _av('SetAVTransportURI', {'CurrentURI': url, 'CurrentURIMetaData': metadata?.toXml() ?? ''});

  Future<void> play() => _av('Play', {'Speed': '1'});
  Future<void> pause() => _av('Pause');
  Future<void> stop() => _av('Stop');
  Future<void> seek(Duration position) => _av('Seek', {'Unit': 'REL_TIME', 'Target': formatUpnpTime(position)});

  Future<TransportInfo> transportInfo() async {
    final r = await _av('GetTransportInfo');
    return TransportInfo(
      state: _state(childText(r, 'CurrentTransportState')),
      status: childText(r, 'CurrentTransportStatus'),
      speed: childText(r, 'CurrentSpeed'),
    );
  }

  Future<PositionInfo> positionInfo() async {
    final r = await _av('GetPositionInfo');
    final duration = parseUpnpTime(childText(r, 'TrackDuration'));
    return PositionInfo(
      // "0:00:00" while loading means unknown, not empty.
      trackDuration: duration == Duration.zero ? null : duration,
      relTime: parseUpnpTime(childText(r, 'RelTime')),
      trackUri: childText(r, 'TrackURI'),
    );
  }

  Future<MediaInfo> mediaInfo() async {
    final r = await _av('GetMediaInfo');
    final duration = parseUpnpTime(childText(r, 'MediaDuration'));
    return MediaInfo(mediaDuration: duration == Duration.zero ? null : duration, currentUri: childText(r, 'CurrentURI'));
  }

  /// 0–100.
  Future<int?> volume() async => int.tryParse(childText(await _rc('GetVolume'), 'CurrentVolume') ?? '');

  Future<void> setVolume(int volume) => _rc('SetVolume', {'DesiredVolume': '${volume.clamp(0, 100)}'});
  Future<void> setMute(bool mute) => _rc('SetMute', {'DesiredMute': mute ? '1' : '0'});
}
