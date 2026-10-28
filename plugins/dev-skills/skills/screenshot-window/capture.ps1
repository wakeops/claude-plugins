<#
.SYNOPSIS
    Finds a window of a running Windows desktop app and screenshots it, or stops the process. See the
    screenshot-window skill's SKILL.md for when to use -Mode Window vs -Mode Screen and general guidance.

.PARAMETER ProcessName
    Name of the process to look for, without .exe (see Get-Process). Required.

.PARAMETER WindowTitle
    Exact title of a specific window (e.g. "Settings") to capture instead of MainWindow.

.PARAMETER Mode
    Window = PrintWindow (WPF-rendered content only, position-independent).
    Screen = real screen capture of the window's bounds + Margin (shows DWM effects: rounded
             corners, drop shadow). Never captures more than the window's own bounds + margin.

.PARAMETER OutFile
    Path to save the PNG to. Required unless -List or -Stop.

.PARAMETER Margin
    Extra pixels captured around the window bounds in Screen mode. Default: 12.

.PARAMETER List
    Print Handle/Title of every visible top-level window owned by the process, then exit.
    Use this to discover a dialog's exact title before passing -WindowTitle.

.PARAMETER Stop
    Stop the process (Stop-Process -Force) instead of capturing anything.

.EXAMPLE
    powershell -File capture.ps1 -ProcessName MyApp -OutFile "$env:TEMP\main.png"

.EXAMPLE
    powershell -File capture.ps1 -ProcessName MyApp -List

.EXAMPLE
    powershell -File capture.ps1 -ProcessName MyApp -WindowTitle "Settings" -OutFile "$env:TEMP\settings.png"

.EXAMPLE
    powershell -File capture.ps1 -ProcessName MyApp -Mode Screen -OutFile "$env:TEMP\rounded_corners.png"

.EXAMPLE
    powershell -File capture.ps1 -ProcessName MyApp -Stop
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProcessName,
    [string]$WindowTitle,
    [ValidateSet("Window", "Screen")]
    [string]$Mode = "Window",
    [string]$OutFile,
    [int]$Margin = 12,
    [switch]$List,
    [switch]$Stop,
    [int]$FocusDelayMs = 500
)

$ErrorActionPreference = "Stop"

if (-not $Stop -and -not $List -and -not $OutFile) {
    Write-Error "Pass -OutFile <path>, or use -List / -Stop."
    exit 1
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class WindowCaptureNative
{
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    // On a display scaled above 100%, a DPI-unaware capture process sees virtualized
    // coordinates (half the real values), so it allocates a half-size bitmap and PrintWindow then
    // renders only the window's top-left quadrant - silently cropping everything on the right and
    // bottom. Declaring DPI awareness makes GetWindowRect return true physical pixels.
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);

    public static List<IntPtr> GetVisibleWindowsForProcess(int pid)
    {
        var result = new List<IntPtr>();
        EnumWindows((hWnd, lParam) =>
        {
            int windowPid;
            GetWindowThreadProcessId(hWnd, out windowPid);
            if (windowPid == pid && IsWindowVisible(hWnd))
            {
                result.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static string GetTitle(IntPtr hWnd)
    {
        var sb = new StringBuilder(256);
        GetWindowText(hWnd, sb, 256);
        return sb.ToString();
    }
}
"@

[WindowCaptureNative]::SetProcessDPIAware() | Out-Null

if ($Stop) {
    Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
    Write-Output "Stopped $ProcessName."
    exit 0
}

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Error "No running process named '$ProcessName'. Launch it first (see SKILL.md)."
    exit 1
}
if ($proc -is [array]) {
    $proc = $proc[0]
}

if ($List) {
    $handles = [WindowCaptureNative]::GetVisibleWindowsForProcess($proc.Id)
    foreach ($h in $handles) {
        $title = [WindowCaptureNative]::GetTitle($h)
        Write-Output "$h  '$title'"
    }
    exit 0
}

$targetHandle = [IntPtr]::Zero
if ($WindowTitle) {
    $handles = [WindowCaptureNative]::GetVisibleWindowsForProcess($proc.Id)
    foreach ($h in $handles) {
        if ([WindowCaptureNative]::GetTitle($h) -eq $WindowTitle) {
            $targetHandle = $h
            break
        }
    }
    if ($targetHandle -eq [IntPtr]::Zero) {
        Write-Error "No visible window titled '$WindowTitle' for process '$ProcessName'. Run -List to see what's available."
        exit 1
    }
} else {
    $targetHandle = $proc.MainWindowHandle
    if ($targetHandle -eq [IntPtr]::Zero) {
        Write-Error "Process '$ProcessName' has no MainWindowHandle yet - it may still be starting. Try again shortly, or pass -WindowTitle."
        exit 1
    }
}

[WindowCaptureNative]::SetForegroundWindow($targetHandle) | Out-Null
Start-Sleep -Milliseconds $FocusDelayMs

$rect = New-Object WindowCaptureNative+RECT
[WindowCaptureNative]::GetWindowRect($targetHandle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) {
    Write-Error "Window has zero/negative size ($width x $height) - it may be minimized."
    exit 1
}

Add-Type -AssemblyName System.Drawing

if ($Mode -eq "Window") {
    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [WindowCaptureNative]::PrintWindow($targetHandle, $hdc, 2) | Out-Null   # 2 = PW_RENDERFULLCONTENT
    $g.ReleaseHdc($hdc)
    $g.Dispose()
} else {
    $x = $rect.Left - $Margin
    $y = $rect.Top - $Margin
    $width = $width + $Margin * 2
    $height = $height + $Margin * 2
    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $width, $height))
    $g.Dispose()
}

$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "Saved: $OutFile (${width}x${height}, mode=$Mode)"
