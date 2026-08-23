---
name: restore-placeholders
description: Before committing or pushing this skills-2026 repo to the remote, when this session actually edited *.tf, *.tfvars, or *.yaml (terraform/eksctl/k8s files), check tracked *.tfvars for personal-value drift (player_number, ssh_password, bucket_suffix 등 로컬 실습값) that must not leak, judge which changed lines are real spec fixes vs local test leftovers, get the user's explicit accept on what to restore, then restore and proceed. Does NOT apply to a commit/push that only touches docs, skills, or other non-infra files this session — skip silently there. Use whenever the user asks to commit or push infra work, or says "커밋해", "푸시해", "이거 원격에 올려", "이 원격 저장소 내에서만 사용", or asks whether a diff has personal test values mixed in.
---

# Catch personal-value drift before it hits the remote

Deploying locally means editing `terraform.tfvars` with a real 비번호, a real SSH password, a real
bucket suffix. Those are per-player/per-machine values. Whatever's already on the remote is what
every set should look like to someone else who clones this repo — so before a push, diff every
changed `*.tfvars` against **the push target** (what the remote currently has for this branch),
not just the last local commit. A leak can already be sitting inside a commit you're about to push.

This is a judgment task, not a mechanical one. Some lines that differ from the remote are legitimate
— e.g. a CIDR changed because a subnet collided. Those must survive. Only the personal-value lines
get reset. Don't auto-restore a fixed key list blindly; read what actually changed and decide.

Region is a special case: it used to be auto-treated as a legitimate spec fix, but once a set's task
frame is settled, its region is locked in too — a differing region at that point almost always means
testing happened against the wrong region/profile, not a real correction. The script now flags
region drift the same way as a personal-value leak.

## Workflow

0. **Gate on whether this session touched infra files at all.** Recall the conversation so far —
   did it edit any `*.tf`, `*.tfvars`, or `*.yaml` (terraform/eksctl/k8s manifest) file? If not —
   e.g. the commit/push is only docs, only this skill's own files, only a Python script unrelated
   to a set — this skill has nothing to check and doesn't apply. Skip everything below silently:
   don't run `report`, don't mention placeholders, just do the commit/push as asked. Leaks only
   happen through tfvars edits, and if none of this session's changes could have touched one,
   running the check is pure overhead.

   If the session did touch infra files, continue to step 1 even if the actual file being
   committed/pushed right now looks unrelated — a `*.tfvars` edit made earlier in the session can
   still be sitting uncommitted or already committed on the branch.

1. **Run `report` internally — don't paste its raw output into chat:**

   ```bash
   py .claude/skills/restore-placeholders/restore_placeholders.py report
   ```

   This is a full scan of every changed top-level `key = value` line versus the push target,
   tagged LEAK / LEGIT / UNSURE (see the script's own classification). Read the result yourself;
   what you say next depends entirely on what's in it.

2. **Stay silent if there's nothing to gate.** If the report has no LEAK and no UNSURE rows —
   either "no drift" or drift that's all LEGIT — say nothing about placeholders at all, in the
   tool call or in chat. No "checked and it's clean", no summary, nothing. Just proceed straight to
   the commit/push the user asked for. This is the common case and it should cost zero extra
   tokens.

3. **If LEAK or UNSURE rows exist, ask before touching anything — and show only those rows.**
   Leave LEGIT rows out of what you show; they're not part of the decision. Restoring a tfvars file
   rewrites something the user is about to commit or push, so fold the confirmation into one
   `AskUserQuestion` covering both the restore and the commit/push itself — don't ask twice.

   For UNSURE rows, judge first (would a second player running this set legitimately land on this
   value too, or is it specific to this machine/player?) and only surface the ones you can't
   resolve yourself; for those, say why you're unsure in a few words, not a full report dump.

   ```
   player_number "1032134" -> "103" (set-02/task-2/module-3-msk/terraform/terraform.tfvars)
   ```

   Options: restore-and-continue / skip restore and continue anyway / cancel. Don't run `restore`
   or the git command until the user picks.

4. **On accept, restore only the confirmed keys:**

   ```bash
   py .claude/skills/restore-placeholders/restore_placeholders.py restore --keys player_number,ssh_password
   ```

   Pass exactly the keys the user just confirmed (comma-separated). Only those lines get reset to
   the remote's current value in every changed tfvars file; every other line — including LEGIT
   changes — is left alone. Omitting `--keys` falls back to the script's `DEFAULT_KEYS` (the
   near-certain leak keys), a convenience for the common case, not a substitute for asking.

5. **Report what was restored in one line per value** (this is the only output the leak path
   produces), then proceed with the staging/commit/push. If nothing needed restoring per step 2,
   there is no step 5 either.

## Why compare against the push target, not HEAD

A restore against `HEAD` only catches uncommitted edits — if the leak already got committed
locally (easy to do when testing right before a push), diffing against `HEAD` finds nothing wrong.
Diffing against the push target (`@{u}`, falling back to `origin/<branch>`, then `origin/main`)
catches the whole set of commits about to go out, not just the working tree.

## Scope

Repo-local by design — this only makes sense inside skills-2026, where the tfvars/remote-parity
convention exists. It only touches tracked `*.tfvars`. `.env`, `.env.ps1`, `outputs.json`, and
`kubeconfig` are gitignored already and can't reach a commit, so there's nothing to check there.

## Checking the script itself

`py .claude/skills/restore-placeholders/restore_placeholders.py --selftest` asserts that `report`
surfaces every changed key (not just the default list), that `restore --keys` touches only the
requested key even when other keys also differ, and that an unchanged file reports/restores
nothing. Run it after editing the script.
