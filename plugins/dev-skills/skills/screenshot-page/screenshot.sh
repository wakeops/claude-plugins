#!/usr/bin/env bash
# Serves a built web app against fixture-driven fake API data, screenshots one route at desktop and phone widths with
# headless Edge/Chrome, then stops the server it started.
#
#   screenshot.sh --dist <dir> --fixtures <fixtures.json> --route </path> [options]
#
#   --dist <dir>            built app output (dist, build, out, ...)                          (required)
#   --fixtures <file>       fixtures JSON for mock-api.js                                      (required)
#   --route </path>         route to open, e.g. /projects/123                                  (required)
#   --out-dir <dir>         where PNGs go (default: $TMPDIR/screenshot-page)
#   --name <name>           file name stem (default: derived from the route)
#   --port <n>              server port (default: 5055; use another to compare fixture sets side by side)
#   --api-prefix <p|none>   how the app reaches its API, see mock-api.js (default: api.)
#   --width/--height <px>   desktop window (default: 1280x1250)
#   --phone-width <px>      phone window width (default: 500, the narrowest headless Chromium lays out)
#   --phone-height <px>     phone window height (default: 1000)
#   --scale <n>             device scale factor, e.g. 3 to zoom in on a detail (default: 1)
#   --no-phone              desktop shot only
#   --budget <ms>           virtual time budget to let the app load its data (default: 15000)
#
# Prints the path of each PNG. Look at every one before sending it anywhere.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

dist="" fixtures="" route="" out_dir="${TMPDIR:-/tmp}/screenshot-page" name="" port=5055 api_prefix="api."
width=1280 height=1250 phone_width=500 phone_height=1000 scale=1 phone=1 budget=15000
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dist)         dist="${2:?--dist needs a value}"; shift 2 ;;
        --fixtures)     fixtures="${2:?--fixtures needs a value}"; shift 2 ;;
        --route)        route="${2:?--route needs a value}"; shift 2 ;;
        --out-dir)      out_dir="${2:?--out-dir needs a value}"; shift 2 ;;
        --name)         name="${2:?--name needs a value}"; shift 2 ;;
        --port)         port="${2:?--port needs a value}"; shift 2 ;;
        --api-prefix)   api_prefix="${2:?--api-prefix needs a value}"; shift 2 ;;
        --width)        width="${2:?--width needs a value}"; shift 2 ;;
        --height)       height="${2:?--height needs a value}"; shift 2 ;;
        --phone-width)  phone_width="${2:?--phone-width needs a value}"; shift 2 ;;
        --phone-height) phone_height="${2:?--phone-height needs a value}"; shift 2 ;;
        --scale)        scale="${2:?--scale needs a value}"; shift 2 ;;
        --budget)       budget="${2:?--budget needs a value}"; shift 2 ;;
        --no-phone)     phone=0; shift ;;
        -h|--help)      usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done
[[ -n "$dist" && -n "$fixtures" && -n "$route" ]] || usage
[[ -d "$dist" ]] || { echo "Dist directory not found: $dist" >&2; exit 1; }
[[ -f "$fixtures" ]] || { echo "Fixtures file not found: $fixtures" >&2; exit 1; }
command -v node >/dev/null || { echo "node is not on PATH." >&2; exit 1; }
route="/${route#/}"

# A Chromium-based browser: Edge ships with Windows; otherwise whatever is on PATH.
browser=""
for candidate in \
    "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
    "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
    "/c/Program Files/Google/Chrome/Application/chrome.exe" \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
    [[ -x "$candidate" ]] && { browser="$candidate"; break; }
done
if [[ -z "$browser" ]]; then
    for candidate in microsoft-edge google-chrome chromium chromium-browser chrome; do
        command -v "$candidate" >/dev/null && { browser="$(command -v "$candidate")"; break; }
    done
fi
[[ -n "$browser" ]] || { echo "No Edge/Chrome/Chromium found." >&2; exit 1; }

# The browser needs C:/... style paths for the screenshot file on Windows, not /c/...
native() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

up() { curl -s -o /dev/null "http://localhost:$port/" 2>/dev/null; }
if up; then
    echo "Something is already listening on port $port; pick another with --port." >&2
    exit 1
fi

mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd)"
name="${name:-$(printf '%s' "$route" | tr -c 'A-Za-z0-9' '-' | sed 's/^-*//; s/-*$//')}"
name="${name:-home}"

server_log="$out_dir/.server-$port.log"
node "$here/mock-api.js" "$dist" "$fixtures" "$port" --api-prefix "$api_prefix" >"$server_log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT   # stops only the server this script started

for _ in $(seq 1 50); do
    up && break
    kill -0 "$server" 2>/dev/null || { echo "Server exited:" >&2; cat "$server_log" >&2; exit 1; }
    sleep 0.2
done
up || { echo "Server did not come up on port $port:" >&2; cat "$server_log" >&2; exit 1; }

shoot() {   # shoot <label> <width> <height>
    local file="$out_dir/$name-$1.png"
    rm -f "$file"
    # timeout matters: headless browsers occasionally hang
    timeout 90 "$browser" --headless --disable-gpu --hide-scrollbars --virtual-time-budget="$budget" \
        --force-device-scale-factor="$scale" --screenshot="$(native "$file")" --window-size="$2,$3" \
        "http://localhost:$port$route" >/dev/null 2>&1 || true
    [[ -s "$file" ]] || { echo "No screenshot produced for $1 (browser failed or timed out)." >&2; exit 1; }
    echo "$file"
}

shoot desktop "$width" "$height"
[[ "$phone" == 1 ]] && shoot phone "$phone_width" "$phone_height"
rm -f "$server_log"
