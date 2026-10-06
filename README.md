# screenshot.sh

Takes screenshots of a list of URLs using your own Chrome profile, so pages you're logged into appear logged in. Screenshots are grouped into folders by date and group name.

macOS only.

## One-time setup

1. **Screen Recording:** open System Settings → Privacy & Security → Screen & System Audio Recording, turn it on for the app you run the script from (Terminal, iTerm, …), then quit and reopen that app. Without this, screenshots show only your desktop wallpaper.
2. **Automation:** on the first run, macOS asks whether your terminal may control Google Chrome. Click **Allow**.
3. **Chrome JavaScript:** in Chrome, turn on View → Developer → **Allow JavaScript from Apple Events**. The script needs this to tell when a page has finished its network requests. Without it, the script waits a fixed 8 seconds per page.
4. Make the script executable:

   ```bash
   chmod +x screenshot.sh
   ```

## Usage

Create a CSV with a `group,url` pair on each line. The header row is optional.

```csv
group,url
Competitors,https://a.com/pricing
Competitors,https://b.com
Our site,https://example.com
```

Run:

```bash
./screenshot.sh urls.csv
```

Output:

```
~/Downloads/2026-10-06-screenshots/
├── Competitors/
│   ├── 001-a.com_pricing.png
│   └── 002-b.com.png
└── Our site/
    └── 001-example.com.png
```

## How it works

For each row, the script:

1. opens the URL in a new Chrome window and waits for the page to load (up to 30s)
2. waits until no network request has finished for 2 seconds (up to 30s), so data the page loads after it opens has arrived
3. waits another 0.5s for the page to draw, takes the screenshot and closes the window

A page that takes about 6 seconds of requests is captured about 9 seconds after opening.

- The script can only see requests once they finish. If one request takes longer than 2 seconds while nothing else finishes, the page may be captured too early. To wait longer, raise `quiet >= 4` in the script (each step is 0.5s).
- Pages that keep polling or hold a live connection open never go quiet, so they always wait the full 30 seconds.

- **Leave the computer alone while it runs.** Chrome is brought to the front for each URL, and anything that covers its window ends up in the screenshot.
- Screenshots show the visible part of the page in a 1440×875 window, not the full scrolling page. To change the size, edit `set bounds of w to {0, 25, 1440, 900}` in the script.
- If you have more than one Chrome profile, the script uses the one you used most recently.
- Rows with no group name are saved in `ungrouped/`. A `/` or `:` in a group name becomes `_`.
- Files are numbered separately in each group. Running the script again on the same day keeps counting up instead of overwriting earlier files.
- CSVs exported from Excel work as-is: quotes, Windows line endings and extra spaces are removed.

## Troubleshooting

| Problem | Fix |
|---|---|
| Screenshots show the desktop wallpaper | Grant Screen Recording permission (setup step 1) and restart the terminal. |
| `Not authorized to send Apple events to Google Chrome` | System Settings → Privacy & Security → Automation → enable Google Chrome for your terminal. |
| `warn: Chrome blocks JavaScript from Apple Events` | Turn on Chrome → View → Developer → Allow JavaScript from Apple Events (setup step 3). |
| Page captured before it finished loading | Raise `quiet >= 4` in the script, or `delay 8` if the Chrome JavaScript setting is off. |
