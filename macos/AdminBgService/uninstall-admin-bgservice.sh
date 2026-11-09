#!/bin/bash
set -euo pipefail

# Removes the VPN service that install-admin-bgservice.sh installed:
#   sudo "…/Resources/TunnelService/uninstall-tunnel-service.sh"

task_destination="/Library/Application Support/Hiddify/AdminBgService/Tropa.app"
task_ext="/Library/Application Support/Hiddify/AdminBgService/HiddifyExt.app"
task_previous="/Library/Application Support/Hiddify/AdminBgService/Hiddify.app"
task_legacy="/Library/Application Support/Hiddify/TunnelService/Hiddify.app"

task_macos_exec() {
  local app="$1"
  local name=""
  if [[ -f "$app/Contents/Info.plist" ]]; then
    name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || true)"
  fi
  if [[ -n "$name" && -x "$app/Contents/MacOS/$name" ]]; then
    printf '%s\n' "$app/Contents/MacOS/$name"
    return 0
  fi
  for name in Tropa Tropa Tropa; do
    if [[ -x "$app/Contents/MacOS/$name" ]]; then
      printf '%s\n' "$app/Contents/MacOS/$name"
      return 0
    fi
  done
  return 1
}

if [[ "$(id -u)" != 0 ]]; then
  echo 'error: run this script with sudo.' >&2
  exit 1
fi
for task_existing in "$task_destination" "$task_ext" "$task_previous" "$task_legacy"; do
  if exec_path="$(task_macos_exec "$task_existing")"; then
    "$exec_path" --tunnel uninstall || true
    break
  fi
done
# Drop both the current and pre-rename install trees.
rm -rf "/Library/Application Support/Hiddify/AdminBgService" \
  "/Library/Application Support/Hiddify/TunnelService"
rmdir "/Library/Application Support/Tropa" 2>/dev/null || true
echo 'Tropa VPN service removed.'
