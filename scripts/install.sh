#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
"$ROOT/scripts/build-app.sh" "$ROOT/dist"
STAGE="$(mktemp -d /Applications/.quota-bar-install.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

pkill -x QuotaBar 2>/dev/null || true
pkill -x CodexMeter 2>/dev/null || true
ditto --norsrc --noextattr --noqtn --noacl "$ROOT/dist/QuotaBar.app" "$STAGE/QuotaBar.app"
xattr -cr "$STAGE/QuotaBar.app"
codesign --force --deep --sign - "$STAGE/QuotaBar.app"
codesign --verify --deep --strict "$STAGE/QuotaBar.app"

PREVIOUS_APP="/Applications/QuotaBar.app"
if [[ ! -d "$PREVIOUS_APP" && -d "/Applications/Codex Meter.app" ]]; then
  PREVIOUS_APP="/Applications/Codex Meter.app"
fi

if [[ -d "$PREVIOUS_APP" ]]; then
  BACKUP="/Applications/.QuotaBar.previous.app"
  rm -rf "$BACKUP"
  mv "$PREVIOUS_APP" "$BACKUP"
  if ! mv "$STAGE/QuotaBar.app" "/Applications/QuotaBar.app"; then
    mv "$BACKUP" "$PREVIOUS_APP"
    exit 1
  fi
  rm -rf "$BACKUP"
else
  mv "$STAGE/QuotaBar.app" "/Applications/QuotaBar.app"
fi

codesign --verify --deep --strict "/Applications/QuotaBar.app"
open "/Applications/QuotaBar.app"
echo "Installed and opened /Applications/QuotaBar.app"
