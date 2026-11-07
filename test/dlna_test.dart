import 'dart:convert';
import 'dart:io';

import 'package:dlna_dart/dlna_dart.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _description = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>1</minor></specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
    <friendlyName>Living room</friendlyName>
    <UDN>uuid:root-1</UDN>
    <deviceList>
      <device>
        <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
        <friendlyName>[LG] webOS TV</friendlyName>
        <manufacturer>LG Electronics</manufacturer>
        <UDN>uuid:renderer-1</UDN>
        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
            <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
            <controlURL>upnp/control/AVTransport1</controlURL>
            <eventSubURL>/upnp/event/AVTransport1</eventSubURL>
          </service>
          <service>
            <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
            <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
            <controlURL>http://10.0.0.9:1234/rc</controlURL>
          </service>
        </serviceList>
      </device>
    </deviceList>
  </device>
</root>''';

void main() {
  group('time', () {
    test('parses UPnP times, fractions and unknowns', () {
      expect(parseUpnpTime('1:02:03'), const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(parseUpnpTime('00:00:01.5'), const Duration(seconds: 1, milliseconds: 500));
      expect(parseUpnpTime('0:00:01.05'), const Duration(seconds: 1, milliseconds: 50));
      expect(parseUpnpTime('0:00:02.1/4'), const Duration(seconds: 2, milliseconds: 250));
      expect(parseUpnpTime('NOT_IMPLEMENTED'), isNull);
      expect(parseUpnpTime(''), isNull);
    });

    test('formats seek targets and DIDL durations', () {
      expect(formatUpnpTime(const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 40)), '01:02:03');
      expect(formatUpnpTime(const Duration(minutes: 2, milliseconds: 40), millis: true), '00:02:00.040');
      expect(formatUpnpTime(const Duration(seconds: -4)), '00:00:00');
    });
  });

  group('ssdp', () {
    final from = InternetAddress('10.0.0.9');

    test('reads a search response', () {
      final r = SsdpResponse.parse(
          'HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLocation: http://10.0.0.9:1234/desc.xml\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSN: uuid:renderer-1::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          'SERVER: WebOS/4.1.0 UPnP/1.0\r\n\r\n',
          from)!;
      expect(r.location, Uri.parse('http://10.0.0.9:1234/desc.xml'));
      expect(r.st, SsdpTarget.mediaRenderer);
      expect(r.uuid, 'uuid:renderer-1');
      expect(r.server, contains('WebOS'));
    });

    test('takes alive notifies, ignores byebyes and other searches', () {
      const alive = 'NOTIFY * HTTP/1.1\r\nLOCATION: http://10.0.0.9/d.xml\r\nNT: upnp:rootdevice\r\nNTS: ssdp:alive\r\nUSN: uuid:x\r\n\r\n';
      expect(SsdpResponse.parse(alive, from)!.st, 'upnp:rootdevice');
      expect(SsdpResponse.parse(alive.replaceFirst('ssdp:alive', 'ssdp:byebye'), from), isNull);
      expect(SsdpResponse.parse('M-SEARCH * HTTP/1.1\r\nST: ssdp:all\r\n\r\n', from), isNull);
      expect(SsdpResponse.parse('HTTP/1.1 200 OK\r\nST: x\r\n\r\n', from), isNull, reason: 'no location');
    });
  });

  group('description', () {
    test('finds embedded devices and resolves URLs against the location', () {
      final devices = UpnpDevice.parseAll(_description, Uri.parse('http://10.0.0.9:1234/dmr/desc.xml'));
      expect(devices.map((d) => d.udn), ['uuid:root-1', 'uuid:renderer-1']);
      expect(devices.first.services, isEmpty, reason: 'the embedded services are not the root\'s');
      final tv = devices.firstWhere((d) => d.isMediaRenderer);
      expect(tv.friendlyName, '[LG] webOS TV');
      expect(tv.service('urn:schemas-upnp-org:service:AVTransport:')!.controlUrl.toString(),
          'http://10.0.0.9:1234/dmr/upnp/control/AVTransport1');
      expect(tv.service('urn:schemas-upnp-org:service:AVTransport:')!.eventSubUrl.toString(), 'http://10.0.0.9:1234/upnp/event/AVTransport1');
      expect(tv.service('urn:schemas-upnp-org:service:RenderingControl:')!.controlUrl.toString(), 'http://10.0.0.9:1234/rc');
    });

    test('URLBase wins when present (UPnP 1.0)', () {
      final xml = _description.replaceFirst('<device>', '<URLBase>http://10.0.0.7:80/</URLBase><device>');
      final tv = UpnpDevice.parseAll(xml, Uri.parse('http://10.0.0.9:1234/dmr/desc.xml')).last;
      expect(tv.services.first.controlUrl.toString(), 'http://10.0.0.7/upnp/control/AVTransport1');
    });
  });

  test('DIDL-Lite escapes the title and announces range seek', () {
    final xml = const DidlItem(title: 'Tom & Jerry <1>', url: 'http://10.0.0.2:8080/t/a?x=1&y=2', duration: Duration(minutes: 90), subtitleUrl: 'http://10.0.0.2:8080/t/s.srt')
        .toXml();
    final doc = XmlDocument.parse(xml);
    expect(doc.findAllElements('dc:title').single.innerText, 'Tom & Jerry <1>');
    final res = doc.findAllElements('res').first;
    expect(res.innerText, 'http://10.0.0.2:8080/t/a?x=1&y=2');
    expect(res.getAttribute('protocolInfo'), contains('DLNA.ORG_OP=01'));
    expect(res.getAttribute('duration'), '01:30:00.000');
    expect(doc.findAllElements('sec:CaptionInfoEx').single.innerText, endsWith('s.srt'));
  });

  group('renderer over SOAP', () {
    late HttpServer server;
    late List<(String action, String body)> calls;
    late DlnaRenderer tv;
    String Function(String action) reply = (_) => '';
    var status = 200;

    setUp(() async {
      calls = [];
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        final action = req.headers.value('SOAPAction')!.split('#').last.replaceAll('"', '');
        calls.add((action, body));
        req.response.statusCode = status;
        req.response.write(reply(action));
        await req.response.close();
      });
      final location = Uri.parse('http://127.0.0.1:${server.port}/dmr/desc.xml');
      tv = DlnaRenderer.of(UpnpDevice.parseAll(_description, location).last)!;
    });
    tearDown(() => server.close(force: true));

    String envelope(String action, String inner) =>
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
        '<u:${action}Response xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">$inner</u:${action}Response></s:Body></s:Envelope>';

    test('setUri sends the URL and the metadata as escaped text', () async {
      reply = (a) => envelope(a, '');
      await tv.setUri('http://10.0.0.2/a?x=1&y=2', metadata: const DidlItem(title: 'A & B', url: 'http://10.0.0.2/a?x=1&y=2'));
      final (action, body) = calls.single;
      expect(action, 'SetAVTransportURI');
      final doc = XmlDocument.parse(body);
      expect(doc.findAllElements('CurrentURI').single.innerText, 'http://10.0.0.2/a?x=1&y=2');
      expect(doc.findAllElements('InstanceID').single.innerText, '0');
      final meta = XmlDocument.parse(doc.findAllElements('CurrentURIMetaData').single.innerText);
      expect(meta.findAllElements('dc:title').single.innerText, 'A & B');
    });

    test('reads position and transport state, any prefix', () async {
      reply = (a) => a == 'GetPositionInfo'
          ? envelope(a, '<Track>1</Track><TrackDuration>01:00:00</TrackDuration><RelTime>0:10:05</RelTime><TrackURI>http://x</TrackURI>')
          : envelope(a, '<CurrentTransportState>PAUSED_PLAYBACK</CurrentTransportState><CurrentTransportStatus>OK</CurrentTransportStatus>');
      final p = await tv.positionInfo();
      expect(p.trackDuration, const Duration(hours: 1));
      expect(p.relTime, const Duration(minutes: 10, seconds: 5));
      final t = await tv.transportInfo();
      expect(t.state, TransportState.paused);
      expect(t.failed, isFalse);
    });

    test('unknown duration while loading is null', () async {
      reply = (a) => envelope(a, '<TrackDuration>0:00:00</TrackDuration><RelTime>NOT_IMPLEMENTED</RelTime>');
      final p = await tv.positionInfo();
      expect(p.trackDuration, isNull);
      expect(p.relTime, isNull);
    });

    test('a SOAP fault becomes an UpnpException with the code', () async {
      status = 500;
      reply = (_) => '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><detail>'
          '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>714</errorCode><errorDescription>Illegal MIME-type</errorDescription></UPnPError>'
          '</detail></s:Fault></s:Body></s:Envelope>';
      await expectLater(
          tv.play(), throwsA(isA<UpnpException>().having((e) => e.code, 'code', 714).having((e) => e.message, 'message', 'Illegal MIME-type')));
    });

    test('seek sends a REL_TIME target', () async {
      reply = (a) => envelope(a, '');
      await tv.seek(const Duration(minutes: 61, seconds: 2));
      final doc = XmlDocument.parse(calls.single.$2);
      expect(doc.findAllElements('Unit').single.innerText, 'REL_TIME');
      expect(doc.findAllElements('Target').single.innerText, '01:01:02');
    });
  });
}
