import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

/// A failed UPnP action: the renderer's own error (code + description from
/// the SOAP fault) or a transport failure (no code).
class UpnpException implements Exception {
  const UpnpException(this.action, this.message, {this.code, this.httpStatus});

  final String action;
  final String message;

  /// UPnP error code (701 "transition not available", 714 "illegal MIME
  /// type", 716 "resource not found"…), when the renderer sent one.
  final int? code;
  final int? httpStatus;

  @override
  String toString() => 'UpnpException($action${code == null ? '' : ' $code'}: $message)';
}

/// Sends SOAP actions to a UPnP service's control URL.
class SoapClient {
  SoapClient({HttpClient? http, this.timeout = const Duration(seconds: 8)}) : _http = http ?? HttpClient();

  final HttpClient _http;
  final Duration timeout;

  /// Calls [action] on [serviceType] with [arguments] (in the order the
  /// service declares them: some renderers are strict) and returns the
  /// `<actionResponse>` element.
  Future<XmlElement> call(Uri controlUrl, String serviceType, String action, Map<String, String> arguments) async {
    final body = utf8.encode(envelope(serviceType, action, arguments));
    try {
      final request = await _http.postUrl(controlUrl).timeout(timeout);
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
        ..set('SOAPAction', '"$serviceType#$action"');
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) throw _fault(action, text, response.statusCode);
      final reply = _findLocal(XmlDocument.parse(text), '${action}Response');
      if (reply == null) throw UpnpException(action, 'no ${action}Response in the reply', httpStatus: response.statusCode);
      return reply;
    } on UpnpException {
      rethrow;
    } on XmlException catch (e) {
      throw UpnpException(action, 'unreadable reply: ${e.message}');
    } on TimeoutException {
      throw UpnpException(action, 'timed out after ${timeout.inSeconds} s');
    } on IOException catch (e) {
      throw UpnpException(action, e.toString());
    }
  }

  void close() => _http.close(force: true);

  /// The request body; values are escaped by the XML builder (a stream URL
  /// with `&` or DIDL-Lite metadata goes in as text).
  static String envelope(String serviceType, String action, Map<String, String> arguments) {
    final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="utf-8"');
    b.element('s:Envelope', attributes: {
      'xmlns:s': 'http://schemas.xmlsoap.org/soap/envelope/',
      's:encodingStyle': 'http://schemas.xmlsoap.org/soap/encoding/',
    }, nest: () {
      b.element('s:Body', nest: () {
        b.element('u:$action', attributes: {'xmlns:u': serviceType}, nest: () {
          arguments.forEach((name, value) => b.element(name, nest: value));
        });
      });
    });
    return b.buildDocument().toXmlString();
  }

  static UpnpException _fault(String action, String body, int status) {
    try {
      final doc = XmlDocument.parse(body);
      final code = int.tryParse(_findLocal(doc, 'errorCode')?.innerText.trim() ?? '');
      final description = _findLocal(doc, 'errorDescription')?.innerText.trim();
      return UpnpException(action, description ?? 'HTTP $status', code: code, httpStatus: status);
    } on XmlException {
      return UpnpException(action, 'HTTP $status', httpStatus: status);
    }
  }
}

/// The first element named [local] whatever its namespace prefix (`u:`,
/// `m:`, none…): renderers disagree on prefixes.
XmlElement? _findLocal(XmlNode root, String local) {
  for (final e in root.descendantElements) {
    if (e.name.local == local) return e;
  }
  return null;
}

/// The trimmed text of the first descendant named [local], or null.
String? childText(XmlElement parent, String local) {
  final e = _findLocal(parent, local);
  final text = e?.innerText.trim();
  return text == null || text.isEmpty ? null : text;
}
