#!/bin/bash
# Opens each URL in your real (logged-in) Chrome and screenshots the window.
# Usage: ./screenshot.sh urls.csv
#   CSV columns: group,url   (header row optional)
#   Saves to ~/Downloads/{date}-screenshots/{group}/NNN-{url}.png
# Needs: Screen Recording + Automation permission for your terminal app (macOS asks on first run).
set -euo pipefail

[ $# -eq 1 ] && [ -f "$1" ] || { echo "Usage: $0 urls.csv"; exit 1; }

OUT="$HOME/Downloads/$(date +%Y-%m-%d)-screenshots"

while IFS=, read -r group url || [ -n "$group" ]; do
  # strip Windows line endings, surrounding quotes and whitespace (Excel exports)
  group=$(echo "$group" | tr -d '\r' | sed -E 's/^[[:space:]"]+|[[:space:]"]+$//g')
  url=$(echo "$url" | tr -d '\r' | sed -E 's/^[[:space:]"]+|[[:space:]"]+$//g')
  [ -z "$url" ] || [ "$url" = "url" ] && continue

  dir="$OUT/$(echo "${group:-ungrouped}" | sed -E 's#[/:]+#_#g')"
  mkdir -p "$dir"
  i=$(( $(find "$dir" -name '*.png' | wc -l) + 1 ))
  name=$(printf '%03d-%s' "$i" "$(echo "$url" | sed -E 's#^https?://##; s#[^A-Za-z0-9._-]+#_#g' | cut -c1-80)")

  # Open in a new Chrome window, wait for load, return page area (below the toolbar) as x,y,w,h
  rect=$(osascript - "$url" <<'EOF'
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
    set {l, t, r, b} to bounds of w
    set {top, pw, ph} to {0, r - l, b - t}
    try
      -- page area only: skip tabs/address bar (assumes 100% zoom, DevTools closed)
      set dims to execute active tab of w javascript "[outerHeight - innerHeight, innerWidth, innerHeight].join()"
      set AppleScript's text item delimiters to ","
      set {top, pw, ph} to {(text item 1 of dims) as integer, (text item 2 of dims) as integer, (text item 3 of dims) as integer}
    on error
      log "warn: can't measure the page area, capturing the whole window"
    end try
    return (l as text) & "," & ((t + top) as text) & "," & (pw as text) & "," & (ph as text)
  end tell
end run
EOF
  ) </dev/null

  if screencapture -x -o -R"$rect" "$dir/$name.png"; then echo "ok   [$group] $url"; else echo "FAIL [$group] $url"; fi
  osascript -e 'tell application "Google Chrome" to close front window' </dev/null
done < "$1"

echo "Saved to $OUT"
