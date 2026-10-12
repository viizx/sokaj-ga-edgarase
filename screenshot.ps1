# Windows version of screenshot.sh: opens each URL in your real (logged-in) Chrome and screenshots the page.
# Usage: powershell -ExecutionPolicy Bypass -File screenshot.ps1 urls.csv [-Wait 8]
#   CSV columns: group,url   (header row optional)
#   Chrome windows can stay in the background; the script captures them directly.
#   Saves to %USERPROFILE%\Downloads\{date}-screenshots\{group}\NNN-{url}.png
param(
  [Parameter(Mandatory)][string]$Csv,
  [int]$Wait = 8  # seconds from opening to capture; Windows can't see network activity in your Chrome
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
public static class Win {
  delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  // Visible top-level Chrome browser windows
  public static List<IntPtr> ChromeWindows() {
    var list = new List<IntPtr>();
    EnumWindows((h, p) => {
      var cls = new StringBuilder(64);
      GetClassName(h, cls, 64);
      if (IsWindowVisible(h) && cls.ToString() == "Chrome_WidgetWin_1") {
        uint pid; GetWindowThreadProcessId(h, out pid);
        try { if (Process.GetProcessById((int)pid).ProcessName == "chrome") list.Add(h); } catch {}
      }
      return true;
    }, IntPtr.Zero);
    return list;
  }

  public static RECT Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }

  // Window contents even when covered by other windows (PW_RENDERFULLCONTENT)
  public static Bitmap Snap(IntPtr h) {
    var r = Rect(h);
    var bmp = new Bitmap(r.Right - r.Left, r.Bottom - r.Top);
    using (var g = Graphics.FromImage(bmp)) { var dc = g.GetHdc(); PrintWindow(h, dc, 2); g.ReleaseHdc(dc); }
    return bmp;
  }
}
"@
[Win]::SetProcessDPIAware() | Out-Null  # real pixels on scaled (125%/150%) displays
$docType = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::Document)

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

  # Open in a new Chrome window and find it by comparing Chrome's windows before and after (max 10s)
  $before = [Win]::ChromeWindows()
  & $chrome --new-window $url
  $win = [IntPtr]::Zero
  for ($t = 0; $t -lt 100 -and $win -eq [IntPtr]::Zero; $t++) {
    Start-Sleep -Milliseconds 100
    $new = [Win]::ChromeWindows() | Where-Object { $before -notcontains $_ } | Select-Object -First 1
    if ($new) { $win = $new }
  }
  if ($win -eq [IntPtr]::Zero) { Write-Host "FAIL [$group] $url (Chrome window didn't open)"; continue }

  Start-Sleep -Seconds $Wait

  try {
    $bmp = [Win]::Snap($win)
    # Crop to the page: its accessibility "document" element excludes tabs/address bar
    $doc = [System.Windows.Automation.AutomationElement]::FromHandle($win).FindFirst([System.Windows.Automation.TreeScope]::Descendants, $docType)
    if ($doc) {
      $d = $doc.Current.BoundingRectangle
      $r = [Win]::Rect($win)
      $x = [Math]::Max(0, [int]$d.X - $r.Left); $y = [Math]::Max(0, [int]$d.Y - $r.Top)
      $crop = New-Object System.Drawing.Rectangle $x, $y, ([Math]::Min([int]$d.Width, $bmp.Width - $x)), ([Math]::Min([int]$d.Height, $bmp.Height - $y))
      $page = $bmp.Clone($crop, $bmp.PixelFormat)
      $bmp.Dispose(); $bmp = $page
    } else {
      Write-Host "warn: can't find the page area, capturing the whole window"
    }
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "ok   [$group] $url"
  } catch {
    Write-Host "FAIL [$group] $url ($_)"
  }

  [Win]::PostMessage($win, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null  # WM_CLOSE
}

Write-Host "Saved to $out"
