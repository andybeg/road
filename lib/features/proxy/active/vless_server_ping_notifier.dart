import 'dart:async';

import 'package:tropa/core/preferences/general_preferences.dart';
import 'package:tropa/features/profile/data/profile_data_providers.dart';
import 'package:tropa/features/profile/notifier/active_profile_notifier.dart';
import 'package:tropa/features/proxy/active/active_proxy_notifier.dart';
import 'package:tropa/features/proxy/data/vless_server_endpoint.dart';
import 'package:tropa/features/proxy/model/proxy_entity.dart';
import 'package:tropa/core_bridge/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum VlessServerPingState { none, testing, reachable, unreachable }

class VlessServerPing {
  const VlessServerPing({required this.state, this.endpoint, this.delayMs});

  const VlessServerPing.none() : this(state: VlessServerPingState.none);
  const VlessServerPing.testing(VlessServerEndpoint endpoint)
    : this(state: VlessServerPingState.testing, endpoint: endpoint);
  const VlessServerPing.reachable(VlessServerEndpoint endpoint, int delayMs)
    : this(state: VlessServerPingState.reachable, endpoint: endpoint, delayMs: delayMs);
  const VlessServerPing.unreachable(VlessServerEndpoint endpoint)
    : this(state: VlessServerPingState.unreachable, endpoint: endpoint);

  final VlessServerPingState state;
  final VlessServerEndpoint? endpoint;
  final int? delayMs;
}

VlessServerEndpoint? _endpointFromProxy(OutboundInfo? proxy) {
  if (proxy == null) return null;
  if (!proxy.typeWithoutStatus.toLowerCase().contains('vless')) return null;
  if (proxy.host.isEmpty || proxy.port <= 0) return null;
  return VlessServerEndpoint(host: proxy.host, port: proxy.port, tag: proxy.tagDisplay);
}

final vlessServerPingProvider = StreamProvider.autoDispose<VlessServerPing>((ref) async* {
  if (!ref.watch(Preferences.vlessServerPingEnabled)) {
    yield const VlessServerPing.none();
    return;
  }
  ref.watch(activeProfileProvider);
  final live = _endpointFromProxy(ref.watch(activeProxyNotifierProvider).valueOrNull);
  VlessServerEndpoint? endpoint = live;
  if (endpoint == null) {
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    if (profile != null) {
      final file = ref.watch(profilePathResolverProvider).file(profile.id);
      if (file.existsSync()) {
        endpoint = VlessServerEndpoints.firstOf(await file.readAsString());
      }
    }
  }

  final interval = ref.watch(Preferences.vlessServerPingInterval);
  final timer = Timer(interval < const Duration(seconds: 5) ? const Duration(seconds: 5) : interval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  if (endpoint == null) {
    yield const VlessServerPing.none();
    return;
  }
  yield VlessServerPing.testing(endpoint);
  final delay = await VlessTcpPing.measure(endpoint.host, endpoint.port);
  yield delay == null ? VlessServerPing.unreachable(endpoint) : VlessServerPing.reachable(endpoint, delay);
});
