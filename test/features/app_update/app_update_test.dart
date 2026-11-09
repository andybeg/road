import 'package:flutter_test/flutter_test.dart';
import 'package:tropa/core/model/environment.dart';
import 'package:tropa/features/app_update/data/github_release_parser.dart';
import 'package:tropa/features/app_update/model/install_kind.dart';

Map<String, dynamic> _release(String tag, {bool draft = false, List<String> assets = const []}) => {
  'tag_name': tag,
  'draft': draft,
  // the release workflow marks every release a pre-release on GitHub
  'prerelease': true,
  'html_url': 'https://github.com/andybeg/tropa/releases/tag/$tag',
  'published_at': '2026-11-01T22:42:47Z',
  'assets': [
    for (final name in assets)
      {
        'name': name,
        'browser_download_url': 'https://github.com/andybeg/tropa/releases/download/$tag/$name',
        'size': 42,
      },
  ],
};

void main() {
  group('a release tag', () {
    test('names its version; the GitHub pre-release flag does not make it one', () {
      final release = GithubReleaseParser.parse(_release('v5.4.0', assets: ['Tropa-MacOS.dmg']))!;
      expect(release.version, '5.4.0');
      expect(release.preRelease, isFalse);
      expect(release.flavor, Environment.prod);
      expect(release.asset('Tropa-MacOS.dmg')!.size, 42);
    });

    test('with a suffix is a pre-release, .dev a dev build', () {
      expect(GithubReleaseParser.parse(_release('v5.5.0-beta.1'))!.preRelease, isTrue);
      final dev = GithubReleaseParser.parse(_release('v5.5.0.dev'))!;
      expect(dev.flavor, Environment.dev);
      expect(dev.version, '5.5.0');
      expect(GithubReleaseParser.parse(_release('v5.4.0+540'))!.buildNumber, '540');
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
          'Tropa-Android-arm64.apk',
          'Tropa-Android-arm7.apk',
          'Tropa-Android-x86_64.apk',
          'Tropa-Android-universal.apk',
          'Tropa-Windows-Setup-x64.exe',
          'Tropa-Windows-Setup-x64.Msix',
          'Tropa-Windows-Portable-x64.zip',
          'Tropa-Linux-x64-AppImage.AppImage',
          'Tropa-Debian-x64.deb',
          'Tropa-MacOS.dmg',
          'Tropa-MacOS-AppStore.dmg',
        ],
      ),
    )!;
    String? asset(InstallKind kind, {List<String> abis = const []}) => kind.assetIn(release, abis: abis)?.name;

    test('an APK is the one of the device ABI, else the universal one', () {
      expect(asset(InstallKind.androidApk, abis: ['arm64-v8a', 'armeabi-v7a']), 'Tropa-Android-arm64.apk');
      expect(asset(InstallKind.androidApk, abis: ['armeabi-v7a']), 'Tropa-Android-arm7.apk');
      expect(asset(InstallKind.androidApk, abis: ['x86_64']), 'Tropa-Android-x86_64.apk');
      expect(asset(InstallKind.androidApk, abis: ['riscv64']), 'Tropa-Android-universal.apk');
      expect(asset(InstallKind.androidApk), 'Tropa-Android-universal.apk');
    });

    test('each desktop install takes its own format, never a store build', () {
      expect(asset(InstallKind.windowsSetup), 'Tropa-Windows-Setup-x64.exe');
      expect(asset(InstallKind.linuxAppImage), 'Tropa-Linux-x64-AppImage.AppImage');
      expect(asset(InstallKind.linuxDeb), 'Tropa-Debian-x64.deb');
      expect(asset(InstallKind.macOS), 'Tropa-MacOS.dmg');
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
    expect(Release.isMsix(r'C:\Program Files\WindowsApps\Tropa_5.4.0.0_x64__abc\hiddify.exe'), isTrue);
    expect(Release.isMsix(r'C:\Program Files\Tropa\Tropa.exe'), isFalse);
  });
}
