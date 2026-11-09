import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/vless_server_endpoint.dart';

void main() {
  group('VlessServerEndpoints.parse', () {
    test('reads a VLESS outbound from JSON', () {
      const raw = '''
{"outbounds":[{"type":"vless","tag":"VPS","server":"203.0.113.10","server_port":8443}]}
''';
      expect(VlessServerEndpoints.parse(raw), [
        const VlessServerEndpoint(host: '203.0.113.10', port: 8443, tag: 'VPS'),
      ]);
    });

    test('skips non-VLESS outbounds', () {
      const raw = '''
{"outbounds":[{"type":"direct","tag":"direct"},{"type":"trojan","server":"203.0.113.9","server_port":443}]}
''';
      expect(VlessServerEndpoints.parse(raw), isEmpty);
    });

    test('reads a vless share link', () {
      const link =
          'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:8443?security=reality&fp=chrome#VPS-8443';
      expect(VlessServerEndpoints.firstOf(link), const VlessServerEndpoint(host: '203.0.113.10', port: 8443, tag: 'VPS-8443'));
    });
  });

  group('VlessTcpPing', () {
    test('measures a listening port', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final delay = await VlessTcpPing.measure(server.address.address, server.port);
      expect(delay, isNotNull);
      expect(delay, greaterThanOrEqualTo(0));
    });

    test('returns null when nothing listens', () async {
      final delay = await VlessTcpPing.measure('127.0.0.1', 1, timeout: const Duration(milliseconds: 400));
      expect(delay, isNull);
    });
  });
}
