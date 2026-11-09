import 'dart:io';

import 'package:path/path.dart' as p;

class ProfilePathResolver {
  const ProfilePathResolver(this._workingDir);

  final Directory _workingDir;

  Directory get directory => Directory(p.join(_workingDir.path, "configs"));

  File file(String fileName) {
    return File(p.join(directory.path, "$fileName.json"));
  }

  File tempFile(String fileName) => file("$fileName.tmp");

  /// Patched copy used at connect time (REALITY key_share). The stored profile stays as imported.
  File runtimeFile(String fileName) => file("$fileName.runtime");
}
