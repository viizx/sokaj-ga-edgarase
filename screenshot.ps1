# Windows version of screenshot.sh: opens each URL in your real (logged-in) Chrome and screenshots the page.
# Usage: powershell -ExecutionPolicy Bypass -File screenshot.ps1 urls.csv [-Wait 8]
#   CSV columns: group,url   (header row optional)
#   Saves to %USERPROFILE%\Downloads\{date}-screenshots\{group}\NNN-{url}.png
param(
  [Parameter(Mandatory)][string]$Csv,
  [int]$Wait = 8  # seconds from opening to capture; Windows can't see network activity in your Chrome
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[Win]::SetProcessDPIAware() | Out-Null  # real pixels on scaled (125%/150%) displays

$chrome = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw "Google Chrome not found" }

$out = Join-Path $env:USERPROFILE "Downloads\$(Get-Date -Format yyyy-MM-dd)-screenshots"

foreach ($row in Import-Csv $Csv -Header group, url) {
  $group = "$($row.group)".Trim()
  $url = "$($row.url)".Trim()
  if (-not $url -or $url -eq 'url') { continue }

  $dir = Join-Path $out ((($group, 'ungrouped') -ne '')[0] -replace '[\\/:*?"<>|]+', '_')
  New-Item -ItemType Directory -Force $dir | Out-Null
  $i = @(Get-ChildItem $dir -Filter *.png).Count + 1
  $slug = $url -replace '^https?://', '' -replace '[^A-Za-z0-9._-]+', '_'
  $file = Join-Path $dir ('{0:D3}-{1}.png' -f $i, $slug.Substring(0, [Math]::Min(80, $slug.Length)))

  # Open in a new Chrome window and wait for it to come to the front (max 5s)
  $before = [Win]::GetForegroundWindow()
  & $chrome --new-window $url
  $win = [IntPtr]::Zero
  for ($t = 0; $t -lt 50 -and $win -eq [IntPtr]::Zero; $t++) {
    Start-Sleep -Milliseconds 100
    $h = [Win]::GetForegroundWindow()
    if ($h -ne $before -and [Win]::FindWindowEx($h, [IntPtr]::Zero, 'Chrome_RenderWidgetHostHWND', $null) -ne [IntPtr]::Zero) { $win = $h }
  }
  if ($win -eq [IntPtr]::Zero) { Write-Host "FAIL [$group] $url (Chrome window didn't open)"; continue }

  Start-Sleep -Seconds $Wait

  # The page is its own child window inside Chrome, so its rectangle excludes tabs/address bar
  $page = [Win]::FindWindowEx($win, [IntPtr]::Zero, 'Chrome_RenderWidgetHostHWND', $null)
  if ($page -eq [IntPtr]::Zero) { $page = $win }
  $r = New-Object Win+RECT
  [Win]::GetWindowRect($page, [ref]$r) | Out-Null

  try {
    $bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "ok   [$group] $url"
  } catch {
    Write-Host "FAIL [$group] $url ($_)"
  }

  [Win]::PostMessage($win, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null  # WM_CLOSE
}

Write-Host "Saved to $out"
