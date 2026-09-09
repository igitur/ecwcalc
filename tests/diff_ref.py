#!/usr/bin/env python3
"""Fast local differential: repo CLI vs the committed oracle reference
(tests/oracle_corpus.jsonl) captured from wine ec.exe /c.

The port deliberately keeps FPC's *more accurate* math where the v1.06
oracle is lossier (Delphi 3-era x87 reductions, truncated constants).
Those expressions are listed in tests/accepted_differences.jsonl and are
reported as ACCEPTED (not failures): the subject output is the correct one
and must not be "fixed" to match the oracle.

Usage: diff_ref.py [subject-cli]
Exit:  0 when every diff is an accepted difference; 1 otherwise.
"""
import json, subprocess, sys

SUBJECT = sys.argv[1] if len(sys.argv) > 1 else "./ec"
CORPUS = sys.argv[2] if len(sys.argv) > 2 else "tests/oracle_corpus.jsonl"
ACCEPTED = "tests/accepted_differences.jsonl"

def subject(e):
    r = subprocess.run([SUBJECT, e], capture_output=True, text=True, timeout=30)
    return r.stdout.strip()

accepted = {}
try:
    for l in open(ACCEPTED):
        l = l.strip()
        if l and not l.startswith("#"):
            a = json.loads(l)
            accepted[a["e"]] = a
except FileNotFoundError:
    pass

rows = [json.loads(l) for l in open(CORPUS) if l.strip()]
diffs = accepted_hits = 0
for r in rows:
    s = subject(r["e"])
    if s != r["o"]:
        if r["e"] in accepted and accepted[r["e"]].get("subject") == s:
            a = accepted[r["e"]]
            print(f"ACCEPTED: {r['e']!r}\n"
                  f"  oracle: {r['o']!r}\n"
                  f"  subj  : {s!r}\n"
                  f"  why   : {a.get('why', '')}", flush=True)
            accepted_hits += 1
        else:
            print(f"DIFF: {r['e']!r}\n  oracle: {r['o']!r}\n  subj  : {s!r}", flush=True)
            diffs += 1
print(f"diff_ref: {len(rows)} exprs, {len(rows)-diffs-accepted_hits} match, "
      f"{accepted_hits} accepted (FPC more accurate), {diffs} unexpected diff", flush=True)
sys.exit(1 if diffs else 0)
