import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:road/core/model/environment.dart';
import 'package:road/features/app_update/model/remote_version_entity.dart';

/// How this copy of the app was installed, which says how it updates itself.
enum InstallKind {
  /// a store's (Google Play, the App Store, the Microsoft Store): the store updates it
  store,

  /// an APK from the releases: the update is installed by the system installer
  androidApk,

  /// Windows, by the setup: the new setup installs over it
  windowsSetup,

  /// Windows, the portable zip: it can not replace itself while it runs
  windowsPortable,

  /// Linux, an AppImage: the new AppImage takes the place of the running one
  linuxAppImage,

  /// Linux, the Debian package: the system's package installer installs the new one
  linuxDeb,

  /// Linux, some other way
  linuxOther,

  /// macOS, outside the App Store: the new disk image opens
  macOS;

  /// What [release] runs as here; [appImage] is the AppImage that runs this copy, if one does.
  static InstallKind detect(Release release, {String? appImage, bool? debianPackage}) {
    if (!release.allowCustomUpdateChecker || kIsWeb) return store;
    if (Platform.isAndroid) return androidApk;
    if (Platform.isWindows) return Environment.isPortable ? windowsPortable : windowsSetup;
    if (Platform.isMacOS) return macOS;
    if (Platform.isLinux) {
      if ((appImage ?? Platform.environment['APPIMAGE'] ?? '').isNotEmpty) return linuxAppImage;
      // the package's file list, which dpkg keeps for each package it installed
      if (debianPackage ?? File('/var/lib/dpkg/info/road.list').existsSync()) return linuxDeb;
      return linuxOther;
    }
    return store;
  }

  /// Whether the app downloads the update and installs it, not only points to it.
  bool get installsItself => switch (this) {
    androidApk || windowsSetup || linuxAppImage || linuxDeb || macOS => true,
    store || windowsPortable || linuxOther => false,
  };

  /// The release file this kind installs from; for an APK, the one built for the device's first
  /// supported ABI ([abis]), else the universal one.
  ReleaseAsset? assetIn(RemoteVersionEntity release, {List<String> abis = const []}) => switch (this) {
    androidApk =>
      release.asset(switch (abis.firstOrNull) {
            'arm64-v8a' => 'Road-Android-arm64.apk',
            'armeabi-v7a' => 'Road-Android-arm7.apk',
            'x86_64' => 'Road-Android-x86_64.apk',
            _ => 'Road-Android-universal.apk',
          }) ??
          release.asset('Road-Android-universal.apk'),
    windowsSetup => release.asset('Road-Windows-Setup-x64.exe'),
    linuxAppImage => release.asset('Road-Linux-x64-AppImage.AppImage'),
    linuxDeb => release.asset('Road-Debian-x64.deb'),
    macOS => release.asset('Road-MacOS.dmg'),
    store || windowsPortable || linuxOther => null,
  };
}
