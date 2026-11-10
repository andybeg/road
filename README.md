# Road

Road is a multi-platform proxy client.

This project is a fork of [hiddify/hiddify-app](https://github.com/hiddify/hiddify-app), licensed under the original GPL-3 additional conditions. See [LICENSE.md](LICENSE.md).

Releases: [github.com/andybeg/road](https://github.com/andybeg/road/releases).
Privacy: [docs/privacy.md](docs/privacy.md). Terms: [docs/terms.md](docs/terms.md).

## What changed in this fork

- Identity: **Road**, Android `com.andybeg.road`, Apple `apple.andybeg.road`
- VLESS Reality handshake: classical `key_share` (as in 4.1.1), multiplex off on Reality
- Optional TCP ping of the VLESS server, configurable in settings
- macOS unsigned builds: Touch ID first when installing the VPN helper

The `hiddify-core` submodule and its gRPC/protobuf names are unchanged: they are the original core protocol.

## Platforms

Android, iOS, Windows, macOS, Linux. Builds are published as GitHub Releases.

## License

Fork of [hiddify/hiddify-app](https://github.com/hiddify/hiddify-app). Same license, including the extra GPL §7 conditions: GitHub fork, GitHub Actions releases, attribution, no similar store names, non-commercial, ShareAlike.
