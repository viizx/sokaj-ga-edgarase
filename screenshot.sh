#!/bin/bash
# Opens each URL in your real (logged-in) Chrome and screenshots the window.
# Usage: ./screenshot.sh urls.csv
#   CSV columns: group,url   (header row optional)
#   Saves to ~/Downloads/{date}-screenshots/{group}/NNN-{url}.png
# Needs: Screen Recording + Automation permission for your terminal app (macOS asks on first run).
set -euo pipefail

[ $# -eq 1 ] && [ -f "$1" ] || { echo "Usage: $0 urls.csv"; exit 1; }

OUT="$HOME/Downloads/$(date +%Y-%m-%d)-screenshots"

# Opens a URL in a new Chrome window, waits for load, returns the page size in pixels as "w h"
read -r -d '' CAPTURE <<'EOF' || true
on run argv
  tell application "Google Chrome"
    activate
    set w to make new window
    set bounds of w to {0, 25, 1440, 900}
    set URL of active tab of w to item 1 of argv
    repeat 60 times
      if not (loading of active tab of w) then exit repeat
      delay 0.5
    end repeat
    -- wait for network idle: no new requests finishing for 1.5s (max 30s)
    try
      execute active tab of w javascript "performance.setResourceTimingBufferSize(100000); 0"
      set lastCount to -1
      set quiet to 0
      repeat 60 times
        set c to (execute active tab of w javascript "performance.getEntriesByType('resource').length") as integer
        if c = lastCount then
          set quiet to quiet + 1
          if quiet >= 3 then exit repeat
        else
          set quiet to 0
          set lastCount to c
        end if
        delay 0.5
      end repeat
    on error
      log "warn: Chrome blocks JavaScript from Apple Events, using a fixed 6s wait instead"
      delay 6
    end try
    delay 0.5 -- let the last responses render
    try
      -- page size, used to cut off tabs/address bar (assumes 100% zoom, DevTools closed)
      return execute active tab of w javascript "innerWidth + ' ' + innerHeight"
    on error
      log "warn: can't measure the page area, capturing the whole window"
      return ""
    end try
  end tell
end run
EOF

# Frontmost Chrome window's real position as "x y w h" (Chrome's own AppleScript bounds are wrong on multi-display setups)
FRONT_WINDOW='ObjC.import("CoreGraphics");
ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements, 0)))
  .filter(w => w.kCGWindowOwnerName == "Google Chrome" && w.kCGWindowLayer == 0)
  .map(w => w.kCGWindowBounds).map(b => [b.X, b.Y, b.Width, b.Height].join(" "))[0]'

while IFS=, read -r group url || [ -n "$group" ]; do
  # strip Windows line endings, surrounding quotes and whitespace (Excel exports)
  group=$(echo "$group" | tr -d '\r' | sed -E 's/^[[:space:]"]+|[[:space:]"]+$//g')
  url=$(echo "$url" | tr -d '\r' | sed -E 's/^[[:space:]"]+|[[:space:]"]+$//g')
  [ -z "$url" ] || [ "$url" = "url" ] && continue

  dir="$OUT/$(echo "${group:-ungrouped}" | sed -E 's#[/:]+#_#g')"
  mkdir -p "$dir"
  i=$(( $(find "$dir" -name '*.png' | wc -l) + 1 ))
  name=$(printf '%03d-%s' "$i" "$(echo "$url" | sed -E 's#^https?://##; s#[^A-Za-z0-9._-]+#_#g' | cut -c1-80)")

  page=$(osascript -e "$CAPTURE" "$url" </dev/null)
  read -r x y w h <<< "$(osascript -l JavaScript -e "$FRONT_WINDOW" </dev/null)"
  # page sits at the bottom of the window; without page size, capture the whole window
  if [ -n "$page" ]; then read -r w ph <<< "$page"; y=$((y + h - ph)); h=$ph; fi

  if screencapture -x -R"$x,$y,$w,$h" "$dir/$name.png"; then echo "ok   [$group] $url"; else echo "FAIL [$group] $url"; fi
  osascript -e 'tell application "Google Chrome" to close front window' </dev/null
done < "$1"

echo "Saved to $OUT"
