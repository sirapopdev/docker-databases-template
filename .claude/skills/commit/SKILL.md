---
name: commit
description: Make a git commit properly — decide what belongs in it, split work that is really two changes, run the repository's own guards first, write the message, and commit. Use this whenever the user asks to commit, to stage and commit, to split changes into commits, to fix up or reword a commit, or asks whether something is ready to commit. Also use it when reviewing a commit message someone wrote. It never commits on its own initiative; it only runs when asked.
---

# Committing

This repo is a Docker Compose template: PostgreSQL 18 plus Databasus for backups. There is no
application code, no build, no CI. The guards below are the only thing standing between a broken
`docker-compose.yml` and someone's `docker compose up`.

## Standing rules for this repository

- **Never commit unless the user asked.** Finished, verified work stays in the working tree. The
  user reviews and stages themselves; a commit made unasked puts work in history before they have
  looked at it.
- **Commit on the branch that is checked out**, including `main`. Do not create a branch first.
- **No trailers.** No `Co-Authored-By`, no generated-with footer. History here carries none.
- **Never `--no-verify`.** A hook that fails is information, not an obstacle. Fix the cause.
- **Never commit `.env`.** It holds real passwords. Only `.env.example` belongs in history, with
  placeholder values like `change-me`.

## Before writing anything

Run these separately and read them — do not chain them:

```bash
git status
```

```bash
git diff --cached --stat
```

Then decide three things:

**1. Is the staged set the whole change?** If files that belong to the same change are unstaged,
say so and ask before staging them. If unrelated work is also staged, propose splitting rather than
committing a mixed change. Never `git add -A` to sweep the tree — that is how `.env`, a scratch
file, or a half-finished experiment enters history. Stage by path.

**2. Is it one logical change?** If the message needs more than about three bullets, or the
subject needs an "and" joining two unrelated things, it is two commits. Split by file group or with
`git add -p`, and order them so each commit works when checked out alone.

Typical pairs that stay together: a new variable in `docker-compose.yml` and its entry in
`.env.example`; a Postgres setting and the `initdb/` script that depends on it. Typical pairs that
split: a stack change and a change under `.claude/`.

**3. Do the guards pass?**

| If the change touched | Run first |
|---|---|
| `docker-compose.yml` or `.env.example` | `docker compose --env-file .env.example config -q` |
| `initdb/*.sh` | `sh -n initdb/<file>.sh` and `git ls-files --eol initdb/` shows `i/lf` |
| image tag, Postgres `command:` flags, or `initdb/` | smoke test below |
| anything | `git diff --cached --check` (whitespace errors) |

A shell script committed with CRLF fails inside the container with `/bin/sh^M: not found`.
`.gitattributes` forces LF for `*.sh`; if a new script type is added, extend it in the same commit.

**Smoke test.** Run it under a separate project name so it never touches the user's real volumes:

```bash
cp .env.example .env.smoke && sed -i 's/^POSTGRES_PORT=.*/POSTGRES_PORT=15432/' .env.smoke
docker compose -p smoke --env-file .env.smoke up -d
docker compose -p smoke --env-file .env.smoke ps    # both services must reach (healthy)
docker compose -p smoke --env-file .env.smoke down -v && rm .env.smoke
```

Port 5432 is taken on this machine and Windows reserves 55432, hence 15432. The fixed
`container_name`s mean this fails with a name conflict if the real stack is running — that is
the safe failure; ask the user before stopping their stack. `down -v` here only deletes the
`smoke_*` volumes. Never run `down -v` without `-p smoke`.

## The message

Format: `type: subject`, conventional types (`feat`, `fix`, `chore`, `docs`, `build`). A scope is
optional; use one only when it narrows things down, e.g. `fix(initdb): ...`.

- **English, subject and body**, matching history (`git log --oneline -20` before writing).
- **Identifiers stay verbatim**: `summarize_wal`, `pg_hba.conf`, `POSTGRES_PORT`, `postgres:18`,
  `databasus/databasus`. Never translate a symbol.
- **Lowercase after the colon, no trailing period, under 72 characters.**
- **Describe the resulting stack, not your session.** "enable `summarize_wal` for Databasus
  incremental backups" describes the repo after the commit; "edit docker-compose.yml" describes
  your afternoon.
- **State the problem in present tense.** The status quo in a message is the repo *without* the
  change: "the image's pg_hba rejects replication connections" — not "pg_hba used to reject…".

Most commits are one line. Write a body only for what the diff cannot say. In this repo that is
usually one of:

- a manual step for existing installs (`initdb/` only runs on an empty volume, so a running
  database needs the change applied by hand)
- a new or renamed variable users must add to their `.env`
- why a version is pinned or bumped, or why an obvious alternative was rejected

## Committing

Use a heredoc so the message keeps its line breaks:

```bash
git commit -F - <<'MSG'
feat: subject line

Body paragraph if there is one.
MSG
```

Then report the result so the user sees what landed:

```bash
git log -1 --oneline --stat
```

Do not push. Pushing is a separate request.

## Amending and rewording

Amending is safe only while the commit is unpushed. Check first:

```bash
git status -sb
```

If the commit has no pushed copy, `git commit --amend` is fine. If it has been pushed, propose a
new commit instead — rewriting published history is the user's call, not yours. To undo the root
commit, `git update-ref -d HEAD` keeps the index; `git reset --soft HEAD~1` does not work there.

## Examples

**Two changes in one commit — split it**

```
feat: bump postgres to 18.1 and add commit skill
```

**Restates the diff — say why instead**

```
fix: update docker-compose.yml

- change volume path
```

Better:

```
fix: mount /var/lib/postgresql so data survives container recreation

postgres:18 keeps data in /var/lib/postgresql/18/docker, not /var/lib/postgresql/data
```

**Good subject, no body needed**

```
chore: pin databasus to 3.60.0
```

## Before you finish

1. Everything staged belongs to one logical change, and nothing that belongs to it is left unstaged
2. `.env` is not staged
3. The guards for the touched files pass
4. Subject: correct type, English, under 72 characters, no trailing period
5. Body exists only if it says something the diff cannot, and does not exceed three bullets
6. No trailers, no `--no-verify`, no new branch, nothing pushed
