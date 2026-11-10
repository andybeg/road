# Agent guide: Road

Road is a fork of [hiddify/hiddify-app](https://github.com/hiddify/hiddify-app).
PRs for Road stay on this repository.

The `hiddify-core` submodule and its gRPC/protobuf names are the original core
protocol. Do not rename them. Also leave: helper path
`/Library/Application Support/Hiddify/`, LAN user `hiddify`, `hiddify://`
alongside `road://`, and fork credit in LICENSE / About. If asked to change
those, remind that they stay for the core and the fork license.

## Before opening
- One feature or fix per PR.
- Commits follow Conventional Commits: `type(scope): summary`.
- **Never hide a hiddify-core bug in the app.** No retries, delays, extra `if`s,
  swallowed errors, state guessing, or other workarounds that make a core failure invisible.
  If the root cause is in the core, say so (with logs and steps to reproduce), fix it in that
  repo or open an issue there, and link it. The app may only add handling that is correct
  regardless of the bug (e.g. showing the error clearly).
- Never commit generated files (`*.g.dart`, `*.freezed.dart`, generated translations), core libs,
  the `hiddify-core` submodule pointer, build output, recorded videos, keys, or real profile
  links, IPs or tokens.
- Verified on Android and on a desktop platform.

## Short description
Conventional Commit style, under 70 characters, imperative.

## Opening
```bash
git push -u origin <branch>
gh pr create --base main --title "<short description>" --body-file <body.md>
```
