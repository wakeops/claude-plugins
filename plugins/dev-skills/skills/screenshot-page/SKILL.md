---
name: screenshot-page
description: Screenshot a page of a built web app, at desktop and phone widths, against fake API data. Use to check a visual change, or to send the user screenshots, without the real backend.
---

# Screenshot a page against fake data

When the app's backend isn't reachable from a dev machine (or you want controlled data), serve the built app together
with a fixture-driven fake API and screenshot it with headless Edge/Chrome. Two files in this skill's directory do the
work, referred to below as `<skill-dir>`:

- `screenshot.sh`: starts the server, waits for it, takes the desktop and phone shots, and stops the server it
  started.
- `mock-api.js`: the server itself (static app plus fixture-driven API). `screenshot.sh` runs it; you only call it
  directly to keep a server up for several shots.

## 1. Build

Build the app the way the project documents (its build script, e.g. `npm run build`) and note the output directory
(`dist`, `build`, `out`, ...). Serve that, not the dev server.

## 2. Write fixtures

A JSON file outside the repo (the scratchpad) listing the routes the page calls. Find the routes in the app's API
client code and the response shapes in its models or types. Example:

```json
[
  { "match": "^/api/projects/123/members$", "body": [ { "id": "1", "name": "Ada", "role": "Owner", "joined": "2020-01-01T00:00:00Z" } ] },
  { "match": "^/api/projects/123$", "body": { "id": "123", "name": "Example Project", "memberCount": 248 } }
]
```

Anchor every pattern (`^...$`); `/api/projects/123` also matches `/api/projects/123/members` otherwise. The first match
wins. Unmatched routes return 404 `{}`, which is how to see a page's error state. A fixture may also set `"status"`.

Make the data realistic and include the awkward cases: long names, missing values, zeros, an empty list, and missing
optional fields.

## 3. Screenshot

```bash
<skill-dir>/screenshot.sh --dist <dist-dir> --fixtures <fixtures.json> --route /projects/123 --out-dir <scratchpad>
```

It prints the path of each PNG (`<name>-desktop.png`, `<name>-phone.png`). Useful options:

| Option | Meaning |
| --- | --- |
| `--api-prefix <p\|none>` | How the app reaches its API. Default `api.`: it calls a host starting with `api.` (`api.<host>`; Chromium resolves `api.localhost` to loopback). `none`: it calls its own origin (`/api/...`), and any path matching a fixture gets the fixture. |
| `--port <n>` | Server port (default 5055). To compare two fixture sets, run the script twice with different ports and `--name`s. |
| `--width/--height` | Desktop window (default 1280x1250). The screenshot is exactly the window, so set the height to what you want to see. |
| `--phone-width/--phone-height` | Phone window (default 500x1000). |
| `--no-phone` | Desktop only. |
| `--scale <n>` | Device scale factor; `3` with a small window zooms in on a detail such as an icon's alignment. |
| `--budget <ms>` | Virtual time given to the app to load its data (default 15000). Raise it for slow pages. |

Run it with no arguments for the full list. It needs `node`, `curl` and an Edge, Chrome or Chromium install (Edge
ships with Windows), and runs in bash (Git Bash on Windows works).

Things to know:

- The script stops only the server it started, even if a shot fails. If the port is already in use it refuses to run
  rather than screenshotting somebody else's server.
- Headless Edge won't lay out below about 500px wide, so a 390px window gives a cropped page, not a phone view. Treat
  500 as the narrowest check, and say so when the real phone width matters.
- The page loads the whole app shell (nav, header); that is expected. Assets hosted elsewhere (CDN images, fonts)
  load from the internet.
- A blank or half-loaded shot usually means the page needed more time (raise `--budget`) or called a route that has no
  fixture (add one, or check the pattern's anchors).

## 4. Look, then send

Read each PNG to check it before sending anything. Send the files the user should see with `SendUserFile`, and remove
screenshots you don't need to keep.

## Keeping a server up

To take many shots against the same data, or drive the page some other way, run the server directly and stop it by the
port it listens on, never with a blanket kill of every `node` process:

```bash
node <skill-dir>/mock-api.js <dist-dir> <fixtures.json> [port] [--api-prefix <prefix>|none]
```
