---
name: commit-and-push
description: Commit and push changes safely. Use whenever asked to commit or push; covers branching, running checks, staging by path, reliable commit messages, and verifying the commit and push actually happened (including PowerShell pitfalls that produce empty commits and stray byte-order marks). To open a pull request afterwards, use open-pr.
---

# Commit and push

## Before committing

- Never commit on the default branch (usually `main`; check with `git symbolic-ref refs/remotes/origin/HEAD`). Branch
  first (`git checkout -b <short-kebab-name>`).
- Run the project's own checks (lint, tests, build) and report failures instead of committing over them. Find the
  commands in CLAUDE.md, AGENTS.md, the README, `package.json` scripts or the CI config; CI usually runs the same set.
- Stage by path (`git add -A src`), not `git add .`, and read `git status --short` before committing.
- Follow the project's commit conventions if it documents any. Otherwise: a short imperative subject
  ("Modernize the settings page"), and a body that says what and why.

## Commit messages

Write the message with a quoted heredoc in a POSIX shell (Bash, zsh, Git Bash); it is the one reliable way:

```bash
git commit -F - <<'EOF'
Subject line

Body.
EOF
```

If the message itself contains a line that is just `EOF`, or an unbalanced quote breaks the command, write the
message to a file with the Write tool and use `git commit -F <file>`.

Check the commit happened: `git log --oneline -2`.

## Push

```
git push -u origin <branch>
```

Verify it landed before moving on (a push can fail without any visible error): `git ls-remote --heads origin <branch>`
must print the branch. The "GitHub found N vulnerabilities" lines in the output are about the default branch, not the
change.

## If you're in PowerShell

Prefer the Bash tool or Git Bash for the above. If you must use PowerShell, especially Windows PowerShell 5.1:

- None of the stdin tricks work, and `git commit -F -` with a here-string commits *nothing* (git reads `-` as a
  pathspec): no `<<<`, no `<<EOF`, no piping into `-F -`. Write the message to a file and pass `-F <file>`.
- `Set-Content -Encoding utf8` and `Out-File` add a byte-order mark, which lands as an invisible character at the start
  of a commit subject. Create the file with the Write tool instead, or write it with
  `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))`.
- git writes progress to stderr, which 5.1 reports as an error. Wrap it: `cmd /c "git push ... 2>&1"`, then verify
  with `git ls-remote` as above.

## After

Report anything that wasn't verified. Line-ending warnings (`LF will be replaced by CRLF`, common on Windows) from git
are harmless.
