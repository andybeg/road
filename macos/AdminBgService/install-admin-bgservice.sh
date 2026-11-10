#!/bin/bash
set -euo pipefail

# Installs the VPN service of builds without a Developer ID: the app's own executable, run as
# `Road --tunnel run` by launchd with administrator rights, which runs the full core. The app
# runs this with administrator authentication; by hand:
#   sudo "/Applications/Road.app/Contents/Resources/TunnelService/install-tunnel-service.sh" \
#     /Applications/Road.app "$USER"

task_source="${1:-}"
task_owner="${2:-${SUDO_USER:-}}"
# Copied app + data live under AdminBgService (matches Go controlDataDir / serviceDataDirectory).
task_destination="/Library/Application Support/Hiddify/AdminBgService/Road.app"

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
  for name in Road Tropa HiddifyExt Hiddify; do
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
if ! task_macos_exec "$task_source" >/dev/null; then
  echo 'error: pass the path of Road.app.' >&2
  exit 1
fi

# The root helper of earlier builds.
launchctl bootout system/com.hiddify.tunnel-helper 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.hiddify.tunnel-helper.plist /Library/PrivilegedHelperTools/com.hiddify.tunnel-helper \
  /var/run/hiddify-tunnel-helper.sock
rm -rf "/Library/Application Support/Hiddify/TunnelHelper"

task_legacy="/Library/Application Support/Hiddify/TunnelService/Hiddify.app"
task_previous="/Library/Application Support/Hiddify/AdminBgService/Hiddify.app"
task_ext="/Library/Application Support/Hiddify/AdminBgService/HiddifyExt.app"
task_tropa="/Library/Application Support/Hiddify/AdminBgService/Tropa.app"
for task_existing in "$task_destination" "$task_tropa" "$task_ext" "$task_previous" "$task_legacy"; do
  if exec_path="$(task_macos_exec "$task_existing")"; then
    "$exec_path" --tunnel uninstall || true
  fi
done
# A root daemon must not run files its user can change, so it runs a root-owned copy of the app.
rm -rf "$task_destination" "$task_tropa" "$task_previous" "/Library/Application Support/Hiddify/TunnelService"
mkdir -p "$(dirname "$task_destination")"
ditto "$task_source" "$task_destination"
xattr -cr "$task_destination"
chown -R root:wheel "$task_destination"
chmod -R go-w "$task_destination"
# Create the control secret for the installing user before the daemon starts listening.
export HIDDIFY_TUNNEL_OWNER="$task_owner"
export HIDDIFY_ADMIN_BG_OWNER="$task_owner"
"$(task_macos_exec "$task_destination")" --tunnel install
echo 'Road VPN service installed.'
