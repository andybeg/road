import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:tropa/core/localization/translations.dart';
import 'package:tropa/core/theme/theme_extensions.dart';
import 'package:tropa/core/widget/shimmer_skeleton.dart';
import 'package:tropa/features/proxy/active/vless_server_ping_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// TCP reachability of the VLESS node's own IP:port, independent of the tunnel URL-test.
class VlessServerPingIndicator extends ConsumerWidget {
  const VlessServerPingIndicator({super.key});

  static const _slotHeight = 36.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ping = ref.watch(vlessServerPingProvider);
    return ping.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: (value) => _Pill(value: value),
      loading: () => ping.hasValue ? _Pill(value: ping.requireValue) : const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _Pill extends ConsumerWidget {
  const _Pill({required this.value});

  final VlessServerPing value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final green = theme.extension<ConnectionButtonTheme>()!.connectedColor!;
    final error = theme.colorScheme.error;
    final state = value.state;
    if (state == VlessServerPingState.none) return const SizedBox.shrink();

    final address = value.endpoint?.address ?? '';
    final (Color color, Color fill, IconData icon, Widget label) = switch (state) {
      VlessServerPingState.reachable => (
        green,
        green.withValues(alpha: .16),
        FluentIcons.desktop_checkmark_24_regular,
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: t.connection.serverPing.ok, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: green)),
              TextSpan(
                text: '  ${value.delayMs} ms',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      VlessServerPingState.unreachable => (
        error,
        error.withValues(alpha: .14),
        FluentIcons.desktop_sync_24_regular,
        Text(t.connection.serverPing.fail, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: error)),
      ),
      VlessServerPingState.testing || VlessServerPingState.none => (
        theme.colorScheme.primary,
        theme.colorScheme.surfaceContainerHigh,
        FluentIcons.desktop_24_regular,
        Semantics(label: t.connection.serverPing.testing, child: const ShimmerSkeleton(width: 72, height: 14)),
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: Tooltip(
          message: address.isEmpty ? t.connection.serverPing.title : '${t.connection.serverPing.title}: $address',
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: () => ref.invalidate(vlessServerPingProvider),
              borderRadius: BorderRadius.circular(18),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: VlessServerPingIndicator._slotHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: color),
                      const Gap(6),
                      Flexible(child: label),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
