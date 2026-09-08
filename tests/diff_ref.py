#!/usr/bin/env python3
"""Fast local differential: repo CLI vs the committed oracle reference
(tests/oracle_corpus.jsonl) captured from wine ec.exe /c.

Usage: diff_ref.py [subject-cli]
"""
import json, subprocess, sys

SUBJECT = sys.argv[1] if len(sys.argv) > 1 else "./ecw"
CORPUS = sys.argv[2] if len(sys.argv) > 2 else "tests/oracle_corpus.jsonl"

def subject(e):
    r = subprocess.run([SUBJECT, e], capture_output=True, text=True, timeout=30)
    return r.stdout.strip()

rows = [json.loads(l) for l in open(CORPUS) if l.strip()]
diffs = 0
for r in rows:
    s = subject(r["e"])
    if s != r["o"]:
        print(f"DIFF: {r['e']!r}\n  oracle: {r['o']!r}\n  subj  : {s!r}", flush=True)
        diffs += 1
print(f"diff_ref: {len(rows)} exprs, {len(rows)-diffs} match, {diffs} diff", flush=True)
sys.exit(1 if diffs else 0)
