import 'dart:io';

import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tropa/core/localization/translations.dart';
import 'package:tropa/core/model/failures.dart';
import 'package:tropa/features/settings/model/config_option_failure.dart';

part 'connection_failure.freezed.dart';

@freezed
sealed class ConnectionFailure with _$ConnectionFailure, Failure {
  const ConnectionFailure._();

  @With<UnexpectedFailure>()
  const factory ConnectionFailure.unexpected([Object? error, StackTrace? stackTrace]) = UnexpectedConnectionFailure;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missingVpnPermission([String? message]) = MissingVpnPermission;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missingNotificationPermission([String? message]) = MissingNotificationPermission;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missingPrivilege() = MissingPrivilege;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.tunAddressInUse() = TunAddressInUse;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.invalidConfigOption([String? message, ConfigOptionFailure? configOptionFailure]) =
      InvalidConfigOption;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.invalidConfig([String? message]) = InvalidConfig;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.backgroundCoreNotAvailable([String? message]) = BackgroundCoreNotAvailable;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missiingWarpLicense() = MissingWarpLicense;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missingPsiphonLicense() = MissingPsiphonLicense;

  factory ConnectionFailure.fromError(Object error, [StackTrace? stackTrace]) => switch (error) {
    ConnectionFailure() => error,
    PathNotFoundException() => const ConnectionFailure.invalidConfig('missing-profile-file'),
    FileSystemException(:final osError) when osError?.errorCode == 2 =>
      const ConnectionFailure.invalidConfig('missing-profile-file'),
    PlatformException(code: 'MACOS_VPN_APPROVAL_REQUIRED', :final message) => ConnectionFailure.missingVpnPermission(
      message,
    ),
    PlatformException(code: 'MACOS_VPN', message: final message?) => ConnectionFailure.unexpected(message, stackTrace),
    _ => ConnectionFailure.unexpected(error, stackTrace),
  };

  @override
  ({String type, String? message}) present(TranslationsEn t) {
    return switch (this) {
      UnexpectedConnectionFailure(:final error) when _isMissingProfileFile(error) => (
        type: t.errors.profiles.notFound,
        message: t.errors.profiles.missingFileMsg,
      ),
      UnexpectedConnectionFailure(:final error) when error != null => (
        type: t.errors.connectivity.unexpected,
        message: "$error",
      ),
      UnexpectedConnectionFailure() => (type: t.errors.connectivity.unexpected, message: null),
      MissingVpnPermission(:final message) => (type: t.errors.connectivity.missingVpnPermission, message: message),
      MissingNotificationPermission(:final message) => (
        type: t.errors.connectivity.missingNotificationPermission,
        message: message,
      ),
      MissingPrivilege() => (type: t.errors.singbox.missingPrivilege, message: t.errors.singbox.missingPrivilegeMsg),
      TunAddressInUse() => (type: t.errors.singbox.tunAddressInUse, message: t.errors.singbox.tunAddressInUseMsg),
      InvalidConfigOption(:final message, :final configOptionFailure) =>
        configOptionFailure?.present(t) ?? (type: t.errors.singbox.invalidConfigOptions, message: message),
      InvalidConfig(message: 'missing-profile-file') => (
        type: t.errors.profiles.notFound,
        message: t.errors.profiles.missingFileMsg,
      ),
      InvalidConfig(:final message) => (type: t.errors.singbox.invalidConfig, message: message),
      BackgroundCoreNotAvailable(:final message) => (type: t.errors.connectivity.core, message: message),
      MissingWarpLicense() => (type: t.errors.warp.missingLicense, message: t.errors.warp.missingLicenseMsg),
      MissingPsiphonLicense() => (type: t.errors.psiphon.missingLicense, message: t.errors.psiphon.missingLicenseMsg),
    };
  }
}

bool _isMissingProfileFile(Object? error) {
  if (error is PathNotFoundException) return true;
  if (error is FileSystemException && error.osError?.errorCode == 2) return true;
  final text = error?.toString() ?? '';
  return text.contains('PathNotFoundException') || text.contains('No such file or directory');
}
