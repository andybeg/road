import 'package:flutter_test/flutter_test.dart';
import 'package:road/core/model/environment.dart';
import 'package:road/features/app_update/data/github_release_parser.dart';
import 'package:road/features/app_update/model/install_kind.dart';

Map<String, dynamic> _release(String tag, {bool draft = false, List<String> assets = const []}) => {
  'tag_name': tag,
  'draft': draft,
  // the release workflow marks every release a pre-release on GitHub
  'prerelease': true,
  'html_url': 'https://github.com/andybeg/road/releases/tag/$tag',
  'published_at': '2026-11-01T22:42:47Z',
  'assets': [
    for (final name in assets)
      {
        'name': name,
        'browser_download_url': 'https://github.com/andybeg/road/releases/download/$tag/$name',
        'size': 42,
      },
  ],
};

void main() {
  group('a release tag', () {
    test('names its version; the GitHub pre-release flag does not make it one', () {
      final release = GithubReleaseParser.parse(_release('v5.4.0', assets: ['Road-MacOS.dmg']))!;
      expect(release.version, '5.4.0');
      expect(release.preRelease, isFalse);
      expect(release.flavor, Environment.prod);
      expect(release.asset('Road-MacOS.dmg')!.size, 42);
    });

    test('with a suffix is a pre-release, .dev a dev build', () {
      expect(GithubReleaseParser.parse(_release('v5.5.0-beta.1'))!.preRelease, isTrue);
      final dev = GithubReleaseParser.parse(_release('v5.5.0.dev'))!;
      expect(dev.flavor, Environment.dev);
      expect(dev.version, '5.5.0');
      expect(GithubReleaseParser.parse(_release('v5.4.0+540'))!.buildNumber, '540');
    });

    test('a Road product suffix is a stable release, not a pre-release', () {
      final road = GithubReleaseParser.parse(_release('v5.5.5-road'))!;
      expect(road.version, '5.5.5');
      expect(road.preRelease, isFalse);
      expect(road.flavor, Environment.prod);
      expect(GithubReleaseParser.parse(_release('v5.5.5-tropa'))!.preRelease, isFalse);
      expect(GithubReleaseParser.parse(_release('v5.5.5-ext'))!.preRelease, isFalse);
    });

    test('that is no version, or a draft, is no release', () {
      expect(GithubReleaseParser.parse(_release('draft')), isNull);
      expect(GithubReleaseParser.parse(_release('v5.4.0', draft: true)), isNull);
    });
  });

  group('the file an install updates from', () {
    final release = GithubReleaseParser.parse(
      _release(
        'v5.4.0',
        assets: [
          'Road-Android-arm64.apk',
          'Road-Android-arm7.apk',
          'Road-Android-x86_64.apk',
          'Road-Android-universal.apk',
          'Road-Windows-Setup-x64.exe',
          'Road-Windows-Setup-x64.Msix',
          'Road-Windows-Portable-x64.zip',
          'Road-Linux-x64-AppImage.AppImage',
          'Road-Debian-x64.deb',
          'Road-MacOS.dmg',
          'Road-MacOS-AppStore.dmg',
        ],
      ),
    )!;
    String? asset(InstallKind kind, {List<String> abis = const []}) => kind.assetIn(release, abis: abis)?.name;

    test('an APK is the one of the device ABI, else the universal one', () {
      expect(asset(InstallKind.androidApk, abis: ['arm64-v8a', 'armeabi-v7a']), 'Road-Android-arm64.apk');
      expect(asset(InstallKind.androidApk, abis: ['armeabi-v7a']), 'Road-Android-arm7.apk');
      expect(asset(InstallKind.androidApk, abis: ['x86_64']), 'Road-Android-x86_64.apk');
      expect(asset(InstallKind.androidApk, abis: ['riscv64']), 'Road-Android-universal.apk');
      expect(asset(InstallKind.androidApk), 'Road-Android-universal.apk');
    });

    test('each desktop install takes its own format, never a store build', () {
      expect(asset(InstallKind.windowsSetup), 'Road-Windows-Setup-x64.exe');
      expect(asset(InstallKind.linuxAppImage), 'Road-Linux-x64-AppImage.AppImage');
      expect(asset(InstallKind.linuxDeb), 'Road-Debian-x64.deb');
      expect(asset(InstallKind.macOS), 'Road-MacOS.dmg');
    });

    test('a store install, the portable zip and other Linux installs download nothing', () {
      for (final kind in [InstallKind.store, InstallKind.windowsPortable, InstallKind.linuxOther]) {
        expect(asset(kind), isNull, reason: '$kind');
        expect(kind.installsItself, isFalse, reason: '$kind');
      }
    });

    test('a release without the file downloads nothing', () {
      final bare = GithubReleaseParser.parse(_release('v5.4.0'))!;
      expect(InstallKind.windowsSetup.assetIn(bare), isNull);
    });
  });

  test('a store release never updates itself', () {
    for (final release in [Release.googlePlay, Release.appStore, Release.microsoftStore]) {
      expect(release.allowCustomUpdateChecker, isFalse, reason: '$release');
      expect(InstallKind.detect(release), InstallKind.store, reason: '$release');
    }
    expect(Release.general.allowCustomUpdateChecker, isTrue);
  });

  test('an MSIX package runs from WindowsApps', () {
    expect(Release.isMsix(r'C:\Program Files\WindowsApps\Road_5.4.0.0_x64__abc\hiddify.exe'), isTrue);
    expect(Release.isMsix(r'C:\Program Files\Road\Road.exe'), isFalse);
  });
}
