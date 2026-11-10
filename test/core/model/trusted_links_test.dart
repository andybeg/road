import 'package:flutter_test/flutter_test.dart';
import 'package:road/core/model/trusted_links.dart';

void main() {
  group("TrustedLinks.isTrusted - trusted", () {
    test("this repository", () {
      expect(TrustedLinks.isTrusted("https://github.com/andybeg/road"), isTrue);
      expect(TrustedLinks.isTrusted("https://github.com/andybeg/road/"), isTrue);
    });

    test("original project", () {
      expect(TrustedLinks.isTrusted("https://github.com/hiddify/hiddify-app"), isTrue);
    });

    test("scheme and www are ignored", () {
      expect(TrustedLinks.isTrusted("http://github.com/andybeg/road"), isTrue);
      expect(TrustedLinks.isTrusted("https://www.github.com/andybeg/road"), isTrue);
    });
  });

  group("TrustedLinks.isTrusted - untrusted", () {
    test("look-alike and extra path", () {
      expect(TrustedLinks.isTrusted("https://github.com/hiddiify/hiddify-app"), isFalse);
      expect(TrustedLinks.isTrusted("https://github.com/andybeg/road/issues"), isFalse);
      expect(TrustedLinks.isTrusted("https://t.me/hiddify"), isFalse);
      expect(TrustedLinks.isTrusted(""), isFalse);
    });
  });
}
