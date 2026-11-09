import 'dart:convert';
import 'dart:io';

/// The VLESS node's own address, as written in the profile — not the IP looked up through the tunnel.
class VlessServerEndpoint {
  const VlessServerEndpoint({required this.host, required this.port, this.tag});

  final String host;
  final int port;
  final String? tag;

  String get address => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is VlessServerEndpoint && other.host == host && other.port == port && other.tag == tag;

  @override
  int get hashCode => Object.hash(host, port, tag);
}

class VlessServerEndpoints {
  static const _vlessType = 'vless';

  /// The first VLESS server in [content], or null when the profile has none.
  static VlessServerEndpoint? firstOf(String content) {
    final all = parse(content);
    return all.isEmpty ? null : all.first;
  }

  static List<VlessServerEndpoint> parse(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.startsWith('{')) return _fromJson(trimmed);
    return _fromShareLinks(content);
  }

  static List<VlessServerEndpoint> _fromJson(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return const [];
      final found = <VlessServerEndpoint>[];
      for (final key in const ['outbounds', 'endpoints']) {
        for (final out in decoded[key] as List? ?? const []) {
          if (out is! Map) continue;
          final type = (out['type'] as String? ?? '').toLowerCase();
          if (type != _vlessType) continue;
          final host = out['server'] as String? ?? '';
          final port = switch (out['server_port']) {
            final int n => n,
            final num n => n.toInt(),
            final String s => int.tryParse(s) ?? 0,
            _ => 0,
          };
          if (host.isEmpty || port <= 0) continue;
          final tag = out['tag'] as String?;
          found.add(VlessServerEndpoint(host: host, port: port, tag: tag));
        }
      }
      return found;
    } on FormatException {
      return const [];
    }
  }

  static List<VlessServerEndpoint> _fromShareLinks(String content) {
    final found = <VlessServerEndpoint>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.scheme.toLowerCase() != _vlessType || uri.host.isEmpty) continue;
      final port = uri.hasPort ? uri.port : 443;
      if (port <= 0) continue;
      final tag = uri.hasFragment && uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment.split(' -> ').first)
          : null;
      found.add(VlessServerEndpoint(host: uri.host, port: port, tag: tag));
    }
    return found;
  }
}

/// TCP connect to the VLESS port. ICMP needs root on Android; the node's own port is the check that matters.
class VlessTcpPing {
  static Future<int?> measure(String host, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }
}
