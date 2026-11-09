import 'package:tropa/features/connection/notifier/connection_notifier.dart';
import 'package:tropa/features/stats/data/stats_data_providers.dart';
import 'package:tropa/core_bridge/generated/v2/hcore/hcore.pb.dart';
import 'package:tropa/core_bridge/init_signal.dart';
import 'package:tropa/utils/custom_loggers.dart';
import 'package:tropa/utils/riverpod_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'stats_notifier.g.dart';

@riverpod
class StatsNotifier extends _$StatsNotifier with AppLogger {
  @override
  Stream<SystemInfo> build() {
    ref.disposeDelay(const Duration(seconds: 10));
    final serviceRunning = ref.watch(serviceRunningProvider);
    // the core gets a new gRPC channel when the app comes back from the background
    ref.watch(coreRestartSignalProvider);
    if (serviceRunning) {
      return ref
          .watch(statsRepositoryProvider)
          .watchStats()
          .map((event) => event.getOrElse((_) => SystemInfo.create()));
    } else {
      return Stream.value(SystemInfo.create());
    }
  }
}
