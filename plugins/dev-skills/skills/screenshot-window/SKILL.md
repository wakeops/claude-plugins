---
name: screenshot-window
description: Launch a Windows desktop app (WPF, WinForms, Win32, Electron) and screenshot its windows to verify a UI change actually works. Use when asked to run the app or visually confirm a desktop UI, not just pass tests. For web pages in a browser use screenshot-page instead.
---

# Running and screenshotting a Windows desktop app

Building and launching are the project's own commands; finding windows and screenshotting them is handled by
`capture.ps1` (same directory as this file, referred to below as `<skill-dir>\capture.ps1`). Use it rather than
re-deriving the P/Invoke boilerplate inline, which is a repeated source of PowerShell syntax errors (colon-parsing in
interpolated strings, `$pid` being a reserved variable, non-ASCII characters silently corrupting `.ps1` files under
Windows PowerShell 5.1's default encoding).

`<Name>` below is the app's process name without `.exe`, as `Get-Process` shows it.

## 1. Build first

Build the way the project documents (`dotnet build`, `npm run build`, ...). If a build fails with errors that look
unrelated to the change (for example missing generated files from a markup compiler), retry once, then do a clean
rebuild (delete `obj`/`bin` or the equivalent) before assuming a real error.

## 2. Launch in the background

Start the app so the shell isn't blocked, then give it a moment to open a window:

```bash
(dotnet run --project <project> --no-build > "$TMPDIR/app_run.log" 2>&1 &)
sleep 3
```

Check the log if the window never appears; a real startup exception shows up there.

## 3. Screenshot it with capture.ps1

```powershell
# Main window, rendered content:
powershell -File "<skill-dir>\capture.ps1" -ProcessName <Name> -OutFile "$env:TEMP\check.png"

# A dialog or secondary window; list titles first if unsure what's open:
powershell -File "<skill-dir>\capture.ps1" -ProcessName <Name> -List
powershell -File "<skill-dir>\capture.ps1" -ProcessName <Name> -WindowTitle "Settings" -OutFile "$env:TEMP\settings.png"

# Real on-screen compositor effects (DWM rounded corners, drop shadow) instead of raw window content:
powershell -File "<skill-dir>\capture.ps1" -ProcessName <Name> -Mode Screen -OutFile "$env:TEMP\screen.png"
```

Two capture modes, and when each matters:

- **`-Mode Window`** (default) uses `PrintWindow`: the window's own raw content, independent of screen position or
  what's on top of it. Use this for layout, bindings, colors, control state, i.e. almost everything.
- **`-Mode Screen`** does a real screen-region capture, scoped to the window's bounds plus a small margin (never
  full-screen; see below). `PrintWindow` does *not* reflect DWM effects like rounded corners or the drop shadow, so
  this is the only way to verify those.

Run `Get-Help <skill-dir>\capture.ps1 -Full` for all parameters (`-Margin`, `-FocusDelayMs`, etc.).

### Captures must be DPI-aware

On a display scaled above 100%, a 900x650 window is larger in physical pixels (1800x1300 at 200%). `capture.ps1` calls
`SetProcessDPIAware()` for this reason: a DPI-unaware process gets *virtualized* coordinates from `GetWindowRect`
(smaller than the real values), allocates a too-small bitmap, and `PrintWindow` then renders only the window's
**top-left portion** into it. The right-hand and bottom edges are silently cropped, with no error or warning.

**This misleads badly.** A cropped capture looks exactly like a layout bug: title-bar buttons, right-aligned controls
and the bottom bar "vanish", centered content appears shifted right, and fixed-size elements look too large. So if
content near the right or bottom edge appears to be missing, **suspect the capture before the layout.** The size the
script prints should match the window's physical size; if it's smaller by the scale factor, the DPI awareness call is
missing.

The cheap way to settle "is this layout or capture?" is to ask the UI framework directly instead of reading pixels:
temporarily log the element's actual width and height, visibility and position. If the numbers are sane, the layout is
fine and the screenshot is lying.

**Never capture the full screen or a whole monitor** (e.g. `Screen.PrimaryScreen.Bounds`) even outside this script.
The machine may have unrelated windows (games, chats, other apps) on other monitors or behind the app, and a
full-screen grab can capture someone else's private content. `-Mode Screen` already scopes correctly; don't build a
wider capture by hand.

## 4. Driving the UI (clicks, typing)

Simulated input (`SetCursorPos` + `mouse_event`) is unreliable: clicks computed from a window's coordinates can land
on unrelated windows on other monitors. If you do it anyway, recompute the target window's rect immediately before
every click (don't reuse a stale rect across calls) and treat it as inherently risky. Prefer read-only verification
(screenshots of the app's default or already-reachable state) over multi-step click sequences. If the app has a
command-line flag, test hook or UI automation interface for reaching a state, use that instead.

## 5. Look, then clean up, always

Read each PNG to check it before sending anything; send the files the user should see with `SendUserFile`. Then stop
the app and remove the screenshots:

```powershell
powershell -File "<skill-dir>\capture.ps1" -ProcessName <Name> -Stop
```

Don't leave the app running or screenshots littered in Temp at the end of a task.

## Real user data: do not touch without asking

Launching the app for verification reads, and can write, its real settings and data (usually under `%AppData%`,
`%LocalAppData%` or the Documents folder). These are the user's, not test fixtures. If a test needs a specific state
(for example, nothing configured), back the file up first, restore it after, and say so. Don't silently leave the
user's real data altered or deleted.
