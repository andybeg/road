#!/bin/bash
set -euo pipefail

# macOS activates a system extension only from an app in /Applications (unless SIP is off), so the
# VPN cannot start from the build folder. This builds Debug, installs it as "Tropa Dev" beside any
# released Tropa, launches it and attaches flutter for hot reload. Extra arguments go to
# `flutter build macos`, for example --dart-define=driver=true.

task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_flutter="${FLUTTER:-$(command -v flutter || true)}"
task_built="$task_root/build/macos/Build/Products/Debug/Tropa.app"
task_app="/Applications/Tropa Dev.app"
task_log="$task_root/build/macos/tropa-dev.log"

if [[ -z "$task_flutter" ]]; then
  echo 'error: flutter is not in PATH. Set FLUTTER to the flutter executable.' >&2
  exit 1
fi

cd "$task_root"
"$task_flutter" build macos --debug "$@"

# Two instances share the core's port and files, so quit every running copy first.
osascript -e 'tell application id "apple.andybeg.tropa" to quit' >/dev/null 2>&1 || true
for _ in $(seq 50); do
  pgrep -f "Tropa.*\.app/Contents/MacOS/Tropa$" >/dev/null || break
  sleep 0.1
done

rm -rf "$task_app"
ditto "$task_built" "$task_app"

# Run the binary itself rather than `open`, so its output, with the VM service URL, reaches the log.
: > "$task_log"
"$task_app/Contents/MacOS/Tropa" >"$task_log" 2>&1 &
task_url=""
for _ in $(seq 300); do
  task_url=$(grep -Eo 'http://127\.0\.0\.1:[0-9]+/[^ ]*' "$task_log" | head -1 || true)
  [[ -n "$task_url" ]] && break
  sleep 0.1
done
if [[ -z "$task_url" ]]; then
  echo "error: Tropa Dev did not report its Dart VM service. See $task_log" >&2
  exit 1
fi

echo "Tropa Dev is running from $task_app"
[[ "${TROPA_DEV_NO_ATTACH:-}" == 1 ]] && exit 0
exec "$task_flutter" attach -d macos --debug-url "$task_url"
