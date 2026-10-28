# claude-plugins

A collection of skills for Claude Code.

## Plugins

### dev-skills

| Skill | Purpose |
| --- | --- |
| `commit-and-push` | Commit and push safely: branch, run checks, stage by path, reliable messages, verified push. Includes PowerShell pitfalls (empty commits, byte-order marks). |
| `open-pr` | Open a GitHub pull request with `gh`: check the branch is pushed, handle login, pass the body from a file. Includes Windows PATH and byte-order-mark notes. |
| `screenshot-page` | Screenshot a page of a built web app at desktop and phone widths, served against fixture-driven fake API data. |
| `screenshot-window` | Launch a Windows desktop app and screenshot its windows (DPI-aware, scoped to the app's own window) to verify UI changes. |
| `ef-core-migrations` | Add EF Core migrations with one helper script: design-time factory, timestamp-named migrations, review checklist, applied on startup. |

## Install

```
/plugin marketplace add <this-repo>
/plugin install dev-skills@wakeops-plugins
```
