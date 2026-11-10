import 'dart:convert';

import 'package:road/singbox/model/singbox_config_enum.dart';

/// Restores the Road 4.1.1 REALITY ClientHello.
///
/// 5.5.5 sends a hybrid X25519MLKEM768 key share (~1.7 KB, two TCP segments).
/// Older Xray (before 26.9.8) and some DPI paths drop that handshake; 4.1.1 sent
/// classical X25519 only. The core already accepts `tls.reality.key_share`.
class RealityHandshake {
  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  /// Patch a stored profile so REALITY outbounds use [keyShare].
  ///
  /// JSON configs are walked in place. Share-link files of only VLESS/Trojan
  /// REALITY URIs become a sing-box outbound list; mixed files get a query
  /// parameter on those URIs instead.
  static String apply(String content, RealityKeyShare keyShare) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return content;
    if (trimmed.startsWith('{')) return _patchJson(trimmed, keyShare) ?? content;
    return _patchShareLinks(content, keyShare);
  }

  static String? _patchJson(String content, RealityKeyShare keyShare) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> && decoded is! List) return null;
      if (!_walk(decoded, keyShare)) return content;
      return '${_jsonEncoder.convert(decoded)}\n';
    } on FormatException {
      return null;
    }
  }

  static bool _walk(dynamic node, RealityKeyShare keyShare) {
    var changed = false;
    if (node is Map<String, dynamic>) {
      if (_patchOutbound(node, keyShare)) changed = true;
      for (final value in node.values) {
        if (_walk(value, keyShare)) changed = true;
      }
    } else if (node is List) {
      for (final item in node) {
        if (_walk(item, keyShare)) changed = true;
      }
    }
    return changed;
  }

  static bool _patchOutbound(Map<String, dynamic> outbound, RealityKeyShare keyShare) {
    final tls = outbound['tls'];
    if (tls is! Map<String, dynamic>) return false;
    final reality = tls['reality'];
    if (reality is! Map<String, dynamic>) return false;
    if (reality['enabled'] != true) return false;
    var changed = false;
    if (reality['key_share'] != keyShare.key) {
      reality['key_share'] = keyShare.key;
      changed = true;
    }
    final multiplex = outbound['multiplex'];
    if (multiplex is Map<String, dynamic> && multiplex['enabled'] == true) {
      multiplex['enabled'] = false;
      changed = true;
    }
    return changed;
  }

  static String _patchShareLinks(String content, RealityKeyShare keyShare) {
    final lines = content.split('\n');
    final converted = <Map<String, dynamic>>[];
    var hasOtherProtocol = false;
    var convertedAny = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final outbound = _shareLinkToRealityOutbound(trimmed, keyShare);
      if (outbound != null) {
        converted.add(outbound);
        convertedAny = true;
        continue;
      }
      if (_looksLikeShareLink(trimmed)) hasOtherProtocol = true;
    }

    if (convertedAny && !hasOtherProtocol) {
      return '${_jsonEncoder.convert({'outbounds': converted})}\n';
    }
    if (!convertedAny) return content;

    return lines
        .map((line) {
          final trimmed = line.trim();
          final uri = Uri.tryParse(trimmed);
          if (uri == null || !_isRealityShareLink(uri)) return line;
          return _withQuery(uri, 'key_share', keyShare.key).toString();
        })
        .join('\n');
  }

  static bool _looksLikeShareLink(String line) {
    final uri = Uri.tryParse(line);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  static Map<String, dynamic>? _shareLinkToRealityOutbound(String line, RealityKeyShare keyShare) {
    final uri = Uri.tryParse(line);
    if (uri == null || !_isRealityShareLink(uri)) return null;

    final params = uri.queryParameters;
    final id = Uri.decodeComponent(uri.userInfo);
    if (id.isEmpty || uri.host.isEmpty) return null;

    final type = uri.scheme == 'trojan' ? 'trojan' : 'vless';
    final port = uri.hasPort ? uri.port : 443;
    final tag = uri.hasFragment && uri.fragment.isNotEmpty
        ? Uri.decodeComponent(uri.fragment.split(' -> ').first)
        : null;
    final sni = params['sni'] ?? params['serverName'] ?? params['peer'] ?? '';
    final fingerprint = params['fp'] ?? params['fingerprint'] ?? 'chrome';
    final publicKey = params['pbk'] ?? params['publicKey'] ?? params['password'] ?? '';
    final shortId = params['sid'] ?? params['shortId'] ?? '';
    final spiderX = params['spx'] ?? params['spiderX'] ?? '';
    final flow = params['flow'] ?? '';
    final alpn = params['alpn'];
    final packetEncoding = params['packetEncoding'] ?? params['packet_encoding'] ?? 'xudp';
    final allowInsecure = params['allowInsecure'] == '1' || params['insecure'] == '1';
    final network = (params['type'] ?? params['network'] ?? 'tcp').toLowerCase();

    final reality = <String, dynamic>{
      'enabled': true,
      'public_key': publicKey,
      'short_id': shortId,
      'key_share': keyShare.key,
    };
    if (spiderX.isNotEmpty) reality['spider_x'] = spiderX;

    final tls = <String, dynamic>{
      'enabled': true,
      'utls': {'enabled': true, 'fingerprint': fingerprint},
      'reality': reality,
    };
    if (sni.isNotEmpty) tls['server_name'] = sni;
    if (allowInsecure) tls['insecure'] = true;
    if (alpn != null && alpn.isNotEmpty) tls['alpn'] = alpn.split(',');

    final outbound = <String, dynamic>{
      'type': type,
      'server': uri.host,
      'server_port': port,
      'tls': tls,
    };
    if (tag != null && tag.isNotEmpty) outbound['tag'] = tag;
    if (type == 'vless') {
      outbound['uuid'] = id;
      outbound['packet_encoding'] = packetEncoding;
    } else {
      outbound['password'] = id;
    }
    if (flow.isNotEmpty) outbound['flow'] = flow;

    final transport = _transport(network, params);
    if (transport != null) outbound['transport'] = transport;
    return outbound;
  }

  static Map<String, dynamic>? _transport(String network, Map<String, String> params) {
    switch (network) {
      case 'ws':
      case 'websocket':
        return {
          'type': 'ws',
          if (params['path'] != null) 'path': params['path'],
          if (params['host'] != null) 'headers': {'Host': params['host']},
        };
      case 'grpc':
        return {
          'type': 'grpc',
          if (params['serviceName'] != null) 'service_name': params['serviceName'],
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          if (params['host'] != null) 'host': params['host'],
          if (params['path'] != null) 'path': params['path'],
        };
      case 'http':
      case 'h2':
        return {
          'type': 'http',
          if (params['host'] != null) 'host': params['host']!.split(','),
          if (params['path'] != null) 'path': params['path'],
        };
      case 'xhttp':
      case 'splithttp':
        return {
          'type': 'xhttp',
          if (params['host'] != null) 'host': params['host'],
          if (params['path'] != null) 'path': params['path'],
        };
      case 'tcp':
      case '':
        return null;
      default:
        return null;
    }
  }

  static bool _isRealityShareLink(Uri uri) {
    if (uri.scheme != 'vless' && uri.scheme != 'trojan') return false;
    final security = (uri.queryParameters['security'] ?? '').toLowerCase();
    return security == 'reality';
  }

  static Uri _withQuery(Uri uri, String key, String value) {
    final params = Map<String, String>.from(uri.queryParameters);
    params[key] = value;
    return uri.replace(queryParameters: params);
  }
}
