---
name: open-pr
description: Open a GitHub pull request with the gh CLI. Use whenever asked to open or create a PR; covers checking the branch is pushed, gh login in non-interactive sessions, and PR bodies passed from a file (plus Windows gh PATH and byte-order-mark pitfalls). The branch must already be pushed; to commit and push first, use commit-and-push.
---

# Open a pull request

## Before opening

The branch must be committed and pushed: `git ls-remote --heads origin <branch>` must print it (see commit-and-push).
Open the PR from a feature branch, with the repo's default branch as `--base`
(`git symbolic-ref refs/remotes/origin/HEAD`).

## Set up gh

`gh auth status` must say logged in. A non-interactive session can't run the login flow; ask the user to run
`gh auth login` in a terminal.

If `gh` isn't found, install it (`winget install GitHub.cli` on Windows, `brew install gh` on macOS, your package
manager on Linux). On Windows, a shell started before the install won't have it on PATH; in PowerShell, refresh it:

```
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
```

## Create it

Put the PR body in a file and pass `--body-file`; a long `--body` string is fragile across shells:

```
gh pr create --base <default-branch> --head <branch> --title "<title>" --body-file <file>
```

Write the body file with the Write tool (or a POSIX shell). In Windows PowerShell 5.1, `Set-Content -Encoding utf8` and
`Out-File` add a byte-order mark, which lands as an invisible character at the start of the PR body; if the text has to
come from PowerShell, write it with
`[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))`.

Follow the repo's PR template or conventions if it has any. Otherwise: a short imperative title, and a body with a
**Summary** of what changed and why.

## After

The command prints the PR URL; give it to the user. If it says there are no commits between the base and the branch,
the commit or push didn't happen: go back and check (commit-and-push). Report anything that wasn't verified.
