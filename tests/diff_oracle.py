#!/usr/bin/env python3
"""Differential harness: repo CLI vs the ECW v1.06 console engine (oracle).

The oracle is ec.exe from the official ecw106_c.zip console package, run
under Wine in its '/c' line-by-line mode over a pty (one process, many
expressions).  After each expression the console echoes it, prints the
result/ERROR line, a blank line, then a fresh prompt.  We read one round
at a time and take the last non-empty line of the round as the result.

Usage:
  diff_oracle.py [subject-cli] corpus.txt
    - subject-cli: default ./ecw
    - corpus.txt  : one expression per line (';' comments allowed)
  Reads env: ECW_ORACLE_DIR (dir containing ec.exe + .dlc plugins)
            WINEPREFIX, WINEDEBUG (honored)
"""
import os, re, select, subprocess, sys, time

ORACLE_DIR = os.environ.get("ECW_ORACLE_DIR", "/tmp/opencode/oracle/ecw106_c")
SUBJECT = "./ecw"
CORPUS = sys.argv[-1]
if len(sys.argv) >= 3:
    SUBJECT = sys.argv[1]

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[=>]")
ENDMARK = "\n\n>"

def _env():
    env = dict(os.environ)
    env.setdefault("WINEDEBUG", "-all")
    env.setdefault("WINEPREFIX", "/tmp/opencode/wineprefix")
    return env

def _stripped(buf):
    return ANSI.sub("", buf.decode("latin1", "replace")).replace("\r", "")

class OracleREPL:
    def __init__(self):
        import pty
        self.master, slave = pty.openpty()
        self.proc = subprocess.Popen(
            ["wine", "ec.exe", "/c"], cwd=ORACLE_DIR, env=_env(),
            stdin=slave, stdout=slave, stderr=slave, close_fds=True)
        os.close(slave)
        self.buf = b""
        self._wait_prompt(timeout=8.0)

    def _drain(self, timeout):
        end = time.time() + timeout
        while time.time() < end:
            r, _, _ = select.select([self.master], [], [], 0.1)
            if r:
                try:
                    d = os.read(self.master, 65536)
                except OSError:
                    break
                if not d:
                    break
                self.buf += d
            elif self.proc.poll() is not None:
                return False
        return self.proc.poll() is None

    def _wait_prompt(self, timeout):
        end = time.time() + timeout
        while time.time() < end:
            self._drain(0.4)
            if _stripped(self.buf).rstrip().endswith(">") or self.buf.endswith(b">"):
                self.buf = b""
                return True
            if self.proc.poll() is not None:
                return False
        return False

    def eval1(self, expr, timeout=10.0):
        self.buf = b""
        os.write(self.master, expr.encode("latin1") + b"\r")
        end = time.time() + timeout
        while time.time() < end:
            if not self._drain(0.2):
                return None
            s = _stripped(self.buf)
            if s.endswith(ENDMARK):
                toks = [t.strip() for t in s.splitlines() if t.strip()]
                self.buf = b""
                if toks and toks[-1] == '>':
                    return toks[-2] if len(toks) >= 2 else None
                if toks:
                    return toks[-1]
                return None
        # timeout: drop whatever was pending, report nothing
        self.buf = b""
        return None

    def close(self):
        try:
            os.write(self.master, b"\x1b")
        except OSError:
            pass
        try:
            self.proc.kill()
        except Exception:
            pass
        try:
            os.close(self.master)
        except OSError:
            pass

def oracle_eval(repl, expr):
    r = repl.eval1(expr)
    if r is not None:
        return r
    # REPL stuck/misbehaved: rebuild once and retry; else single-shot fallback
    repl.close()
    new = OracleREPL()
    repl.__dict__.update(new.__dict__)
    r = repl.eval1(expr)
    if r is not None:
        return r
    sub = subprocess.run(["wine", "ec.exe", expr], cwd=ORACLE_DIR,
                         env=_env(), capture_output=True, text=True, timeout=20)
    lines = sub.stdout.splitlines()
    return "\n".join(lines[1:]).strip() if len(lines) > 1 else None

def subject_eval(expr):
    r = subprocess.run([SUBJECT, expr], capture_output=True, text=True, timeout=30)
    return r.stdout.strip()

def load_corpus(path):
    out = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(";"):
                continue
            out.append(line)
    return out

def main():
    if not CORPUS:
        print(__doc__)
        return 1
    exprs = load_corpus(CORPUS)
    repl = OracleREPL()
    diffs = 0
    fails = 0
    for i, e in enumerate(exprs):
        o = oracle_eval(repl, e)
        s = subject_eval(e)
        if o is None:
            print(f"ORACLE-FAIL [{i}]: {e!r}", flush=True)
            fails += 1
        elif o != s:
            print(f"DIFF [{i}]: {e!r}\n  oracle: {o!r}\n  subj  : {s!r}", flush=True)
            diffs += 1
    repl.close()
    total = len(exprs)
    ok = total - diffs - fails
    print(f"diff_oracle: {total} exprs, {ok} match, {diffs} diff, {fails} oracle-fail", flush=True)
    return 1 if (diffs or fails) else 0

if __name__ == "__main__":
    sys.exit(main())
