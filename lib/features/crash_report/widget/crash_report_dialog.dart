import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tropa/core/localization/translations.dart';
import 'package:tropa/core/model/constants.dart';
import 'package:tropa/core/notification/in_app_notification_controller.dart';
import 'package:tropa/features/crash_report/data/diagnostics_exporter.dart';
import 'package:tropa/features/log/overview/logs_modals.dart';
import 'package:tropa/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _log = appLogger('CrashReportDialog');

/// Shown on the first run after a crash: send the diagnostics zip, or not now. Either way it
/// is not shown again for the same crash.
class CrashReportDialog extends HookConsumerWidget {
  const CrashReportDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return AlertDialog(
      icon: const Icon(Icons.bug_report_outlined),
      title: Text(t.dialogs.crashReport.title),
      content: ConstrainedBox(constraints: AlertDialogConst.boxConstraints, child: Text(t.dialogs.crashReport.msg)),
      actions: [
        TextButton(onPressed: () => context.pop(), child: Text(t.common.later)),
        FilledButton(
          onPressed: () async {
            context.pop();
            await shareDiagnostics(ref);
          },
          child: Text(t.dialogs.crashReport.send),
        ),
      ],
    );
  }
}

/// Builds the diagnostics zip and hands it to the share sheet, or to a save dialog on desktop.
Future<void> shareDiagnostics(WidgetRef ref) async {
  final t = ref.read(translationsProvider).requireValue;
  final notifications = ref.read(inAppNotificationControllerProvider);
  try {
    final file = await ref.read(diagnosticsExporterProvider).export();
    await saveFileAs(file, t: t, notifications: notifications);
  } catch (e, stack) {
    _log.error('exporting the diagnostics failed: $e', e, stack);
    notifications.showErrorToast(t.pages.logs.fileSaveFailed);
  }
}
