#!/usr/bin/env python3
"""Capture the oracle (wine ec.exe /c) output for every expression in a
corpus file into tests/oracle_corpus.jsonl as {"e": expr, "o": output}.

Usage: capture_oracle.py corpus.txt out.jsonl
"""
import json, sys
import diff_oracle as d

def main():
    corpus, out = sys.argv[1], sys.argv[2]
    exprs = d.load_corpus(corpus)
    repl = d.OracleREPL()
    rows = []
    for e in exprs:
        o = d.oracle_eval(repl, e)
        if o is None:
            print(f"ORACLE-FAIL: {e!r}", flush=True)
            continue
        rows.append({"e": e, "o": o})
    repl.close()
    with open(out, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"captured {len(rows)}/{len(exprs)}", flush=True)

if __name__ == "__main__":
    main()
