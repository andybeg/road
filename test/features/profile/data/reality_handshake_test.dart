import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/reality_handshake.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';

void main() {
  const vlessReality =
      'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:8443'
      '?encryption=none&flow=xtls-rprx-vision&security=reality'
      '&sni=www.example.com&fp=chrome&pbk=publicKeyHere&sid=0ee92808'
      '&type=tcp#VPS-8443';

  group('RealityHandshake JSON', () {
    test('sets classical key_share on a REALITY outbound', () {
      const raw = '''
{
  "outbounds": [
    {
      "type": "vless",
      "server": "203.0.113.10",
      "server_port": 8443,
      "uuid": "11111111-1111-1111-1111-111111111111",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "www.example.com",
        "utls": {"enabled": true, "fingerprint": "chrome"},
        "reality": {"enabled": true, "public_key": "publicKeyHere", "short_id": "0ee92808"}
      },
      "multiplex": {"enabled": true, "protocol": "h2mux"}
    }
  ]
}
''';
      final patched = jsonDecode(RealityHandshake.apply(raw, RealityKeyShare.classical)) as Map<String, dynamic>;
      final outbound = (patched['outbounds'] as List).first as Map<String, dynamic>;
      final reality = (outbound['tls'] as Map)['reality'] as Map<String, dynamic>;
      expect(reality['key_share'], 'classical');
      expect((outbound['multiplex'] as Map)['enabled'], isFalse);
    });

    test('overwrites an existing key_share with hybrid', () {
      const raw = '''
{"outbounds":[{"type":"vless","tls":{"enabled":true,"reality":{"enabled":true,"public_key":"x","short_id":"ab","key_share":"classical"}}}]}
''';
      final patched = jsonDecode(RealityHandshake.apply(raw, RealityKeyShare.hybrid)) as Map<String, dynamic>;
      final reality =
          (((patched['outbounds'] as List).first as Map)['tls'] as Map)['reality'] as Map<String, dynamic>;
      expect(reality['key_share'], 'hybrid');
    });

    test('leaves non-REALITY TLS outbounds unchanged', () {
      const raw = '{"outbounds":[{"type":"vless","tls":{"enabled":true,"server_name":"example.com"}}]}\n';
      expect(RealityHandshake.apply(raw, RealityKeyShare.classical), raw);
    });
  });

  group('RealityHandshake share links', () {
    test('turns a REALITY VLESS URI into JSON with classical key_share', () {
      final patched = jsonDecode(RealityHandshake.apply(vlessReality, RealityKeyShare.classical)) as Map<String, dynamic>;
      final outbound = (patched['outbounds'] as List).single as Map<String, dynamic>;
      expect(outbound['type'], 'vless');
      expect(outbound['server'], '203.0.113.10');
      expect(outbound['server_port'], 8443);
      expect(outbound['flow'], 'xtls-rprx-vision');
      expect(outbound['tag'], 'VPS-8443');
      final tls = outbound['tls'] as Map<String, dynamic>;
      expect(tls['server_name'], 'www.example.com');
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
      expect((tls['reality'] as Map)['key_share'], 'classical');
      expect((tls['reality'] as Map)['short_id'], '0ee92808');
      expect(outbound.containsKey('transport'), isFalse);
    });

    test('keeps mixed subscriptions as share links and adds the query', () {
      final mixed = '$vlessReality\nhy2://secret@203.0.113.11:443?sni=example.com#other';
      final patched = RealityHandshake.apply(mixed, RealityKeyShare.classical);
      expect(patched.startsWith('{'), isFalse);
      expect(patched, contains('key_share=classical'));
      expect(patched, contains('hy2://secret@203.0.113.11:443'));
    });

    test('leaves a non-REALITY VLESS URI unchanged', () {
      const tlsOnly = 'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443?security=tls&sni=example.com#plain';
      expect(RealityHandshake.apply(tlsOnly, RealityKeyShare.classical), tlsOnly);
    });
  });
}
