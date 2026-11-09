import 'dart:async';

import 'package:tropa/core/directories/directories_provider.dart';
import 'package:tropa/core/notification/in_app_notification_controller.dart';
import 'package:tropa/core_bridge/core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'core_service_provider.g.dart';

@Riverpod(keepAlive: true, dependencies: [AppDirectories, inAppNotificationController])
CoreService coreService(Ref ref) {
  final service = CoreService(ref);
  ref.onDispose(() => unawaited(service.core.dispose()));
  return service;
}
