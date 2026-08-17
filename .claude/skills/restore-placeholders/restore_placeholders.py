# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
"""Catch personal-value drift in tracked *.tfvars before it reaches the remote.

The comparison baseline is whatever is already on the remote (the push target),
not the last local commit -- a local commit can itself contain the leak, and by
the time you're about to push, "what's on the remote now" is the thing that
must not regress. There is no separate placeholder registry: the remote copy
*is* the reference.

`report` pre-classifies every changed line as LEAK / LEGIT / UNSURE using cheap,
generalizable heuristics (key name for LEAK, value *shape* for both -- CIDR/
version/instance-type patterns read as LEGIT, region/account-id/IP/password
patterns read as LEAK, since key names differ across the repo's 14+ tfvars
files but those shapes don't). Only UNSURE lines need an
actual judgment call; LEAK/LEGIT come with a one-word reason so that call can
be skimmed instead of re-derived. `report` also prints the exact `restore
--keys ...` invocation for the LEAK set, ready to run once the user accepts.

Usage:
    py restore_placeholders.py report [--against REF]
    py restore_placeholders.py restore --keys k1,k2,... [--against REF]
    py restore_placeholders.py --selftest
"""

import re
import subprocess
import sys

# Exact key names that are leaks whenever they differ from the remote, and the
# fallback for `restore` when --keys is omitted.
DEFAULT_KEYS = [
    "player_number",
    "bibunho",
    "bucket_suffix",
    "ssh_password",
    "db_password",
    "origin_verify_value",
]

ASSIGN_RE = re.compile(r"^[ \t]*([a-zA-Z_][a-zA-Z0-9_]*)[ \t]*=[ \t]*(\S.*)$", re.MULTILINE)

# Value *shapes* that generalize across sets, unlike key names.
_LEGIT_VALUE_RES = [
    (re.compile(r'^"(\d{1,3}\.){3}\d{1,3}/\d{1,2}"$'), "CIDR-shaped"),
    (re.compile(r'^"\d+\.\d+(\.\d+)?"$'), "version-shaped"),
    (re.compile(r'^"[a-zA-Z][\w]*\.[a-zA-Z][\w.]*"$'), "instance-type-shaped"),
    (re.compile(r'^(true|false)$'), "boolean"),
    (re.compile(r'^\d+$'), "unquoted number (size/count, not a string id)"),
]
_LEAK_VALUE_RES = [
    # region used to be auto-LEGIT, but once a set's task frame is locked in, its
    # region is fixed too -- a differing region at that point is a local-test
    # artifact (wrong tab/profile), not a spec fix, so it's flagged like a leak.
    (re.compile(r'^"[a-z]{2}-[a-z]+-\d"$'), "region-shaped (task frame is locked in -- treat a differing region as drift)"),
    (re.compile(r'^"\d{12}"$'), "12-digit value (AWS account id shape)"),
    (re.compile(r'^"(\d{1,3}\.){3}\d{1,3}"$'), "IP-shaped"),
    (re.compile(r'^"(?=[^"]*[a-zA-Z])(?=[^"]*\d)[^"]{6,}"$'), "password-shaped (mixed letters+digits, len>=6)"),
]


def classify(key, value):
    """-> (tag, reason). LEAK/LEGIT are heuristic-confident; UNSURE needs a human/model call."""
    if key in DEFAULT_KEYS:
        return "LEAK", f"key name '{key}' is a known personal-value field"
    for pat, reason in _LEGIT_VALUE_RES:
        if pat.match(value):
            return "LEGIT", reason
    for pat, reason in _LEAK_VALUE_RES:
        if pat.match(value):
            return "LEAK", reason
    return "UNSURE", "no heuristic matched -- read the surrounding diff"


def git(*args):
    # encoding pinned: Windows text mode defaults to cp949 here and chokes on
    # the Korean comments in these files
    return subprocess.run(
        ["git", *args], capture_output=True, text=True, encoding="utf-8", check=True
    ).stdout


def push_target():
    """Best-guess ref for 'what's currently on the remote for this branch'."""
    try:
        return git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}").strip()
    except subprocess.CalledProcessError:
        pass
    branch = git("branch", "--show-current").strip()
    for candidate in (f"origin/{branch}", "origin/main", "origin/master"):
        try:
            git("rev-parse", "--verify", candidate)
            return candidate
        except subprocess.CalledProcessError:
            continue
    raise SystemExit("no upstream and no origin/main|master -- pass --against explicitly")


def changed_tfvars(ref):
    out = git("diff", "--name-only", ref, "--", "*.tfvars")
    return [p for p in out.splitlines() if p.strip()]


def assignments(text):
    """key -> value for every top-level assignment line. Last one wins, which
    matches how a second assignment of the same key would actually be read."""
    return {m.group(1): m.group(2) for m in ASSIGN_RE.finditer(text)}


def diff_file(ref_text, work_text):
    """(key, ref_value, local_value) for every key whose value differs."""
    ref_kv = assignments(ref_text)
    work_kv = assignments(work_text)
    return [
        (key, ref_kv[key], value)
        for key, value in work_kv.items()
        if key in ref_kv and ref_kv[key] != value
    ]


def restore_keys(ref_text, work_text, keys):
    """Return work_text with each of `keys` reset to its ref_text value."""
    ref_kv = assignments(ref_text)
    hits = []

    def repl(m):
        key, value = m.group(1), m.group(2)
        if key in keys and key in ref_kv and ref_kv[key] != value:
            hits.append((key, value, ref_kv[key]))
            return f"{key} = {ref_kv[key]}"
        return m.group(0)

    return ASSIGN_RE.sub(repl, work_text), hits


def cmd_report(ref):
    rows = []  # (tag, reason, path, key, ref_value, local_value)
    for path in changed_tfvars(ref):
        ref_text = git("show", f"{ref}:{path}")
        with open(path, encoding="utf-8") as f:
            work_text = f.read()
        for key, ref_value, local_value in diff_file(ref_text, work_text):
            tag, reason = classify(key, local_value)
            rows.append((tag, reason, path, key, ref_value, local_value))

    if not rows:
        print(f"no drift vs {ref}")
        return 0

    for tag in ("LEAK", "LEGIT", "UNSURE"):
        group = [r for r in rows if r[0] == tag]
        if not group:
            continue
        print(f"-- {tag} ({len(group)}) --")
        for _, reason, path, key, ref_value, local_value in group:
            print(f"{path}: {key}: {ref_value} -> {local_value}  [{reason}]")

    leak_keys = sorted({key for tag, _, _, key, _, _ in rows if tag == "LEAK"})
    if leak_keys:
        print(f"suggested: restore --keys {','.join(leak_keys)}")
    return 0


def cmd_restore(ref, keys):
    keys = set(keys)
    drifted = False
    for path in changed_tfvars(ref):
        ref_text = git("show", f"{ref}:{path}")
        with open(path, encoding="utf-8") as f:
            work_text = f.read()
        fixed, hits = restore_keys(ref_text, work_text, keys)
        if not hits:
            continue
        drifted = True
        for key, local, restored in hits:
            print(f"{path}: {key} {local} -> {restored} (restored)")
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(fixed)
    if not drifted:
        print("nothing to restore")
    return 0


def parse_args(argv):
    if not argv or argv[0] not in ("report", "restore"):
        raise SystemExit(__doc__)
    sub = argv[0]
    ref = None
    keys = None
    i = 1
    while i < len(argv):
        if argv[i] == "--against" and i + 1 < len(argv):
            ref = argv[i + 1]
            i += 2
        elif argv[i] == "--keys" and i + 1 < len(argv):
            keys = [k.strip() for k in argv[i + 1].split(",") if k.strip()]
            i += 2
        else:
            raise SystemExit(f"unrecognized argument: {argv[i]}")
    return sub, ref or push_target(), keys


def main(argv):
    sub, ref, keys = parse_args(argv)
    if sub == "report":
        return cmd_report(ref)
    return cmd_restore(ref, keys if keys is not None else DEFAULT_KEYS)


def selftest():
    # -- classify: the whole point of this rewrite, so it gets the most cases --
    assert classify("player_number", '"1032134"')[0] == "LEAK"  # known key wins outright
    assert classify("db_password", '"anything"')[0] == "LEAK"
    assert classify("region", '"us-east-1"')[0] == "LEAK"  # task frames are locked -- region drift is flagged now
    assert classify("vpc_cidr", '"192.168.0.0/16"')[0] == "LEGIT"  # CIDR shape
    assert classify("kafka_version", '"3.6.0"')[0] == "LEGIT"  # version shape
    assert classify("broker_instance_type", '"kafka.t3.small"')[0] == "LEGIT"  # instance-type shape
    assert classify("broker_volume_size", "10")[0] == "LEGIT"  # unquoted number = config size
    assert classify("account_id", '"123456789012"')[0] == "LEAK"  # AWS account id shape
    assert classify("bastion_ip", '"10.0.1.23"')[0] == "LEAK"  # IP shape
    assert classify("api_key", '"Sk1ll53##xyz"')[0] == "LEAK"  # password shape
    assert classify("some_new_field", '"abc"')[0] == "UNSURE"  # nothing matches -> ask, don't guess

    # -- diff/restore plumbing, same contract as before --
    ref = 'player_number = "00"\nregion = "us-west-2"\n'
    work = 'player_number = "1032134"\nregion = "ap-northeast-1"\n'

    diffs = diff_file(ref, work)
    assert diffs == [
        ("player_number", '"00"', '"1032134"'),
        ("region", '"us-west-2"', '"ap-northeast-1"'),
    ], diffs

    # restore only touches the keys it's told to -- region survives even
    # though it also differs, because the caller judged it a real edit
    fixed, hits = restore_keys(ref, work, {"player_number"})
    assert 'player_number = "00"' in fixed, fixed
    assert 'region = "ap-northeast-1"' in fixed, fixed
    assert hits == [("player_number", '"1032134"', '"00"')], hits

    # unchanged input reports/restores nothing
    assert diff_file(ref, ref) == []
    assert restore_keys(ref, ref, {"player_number"})[1] == []

    print("selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        sys.exit(main(sys.argv[1:]))
