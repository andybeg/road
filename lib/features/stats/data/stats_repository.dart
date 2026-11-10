import 'package:fpdart/fpdart.dart';
import 'package:road/core/utils/exception_handler.dart';
import 'package:road/features/stats/model/stats_failure.dart';
import 'package:road/core_bridge/generated/v2/hcore/hcore.pb.dart';
import 'package:road/core_bridge/core_service.dart';
import 'package:road/utils/custom_loggers.dart';

abstract interface class StatsRepository {
  Stream<Either<StatsFailure, SystemInfo>> watchStats();
}

class StatsRepositoryImpl with ExceptionHandler, InfraLogger implements StatsRepository {
  StatsRepositoryImpl({required this.singbox});

  final CoreService singbox;

  @override
  Stream<Either<StatsFailure, SystemInfo>> watchStats() {
    return singbox.watchStats().handleExceptions(StatsUnexpectedFailure.new);
  }
}
