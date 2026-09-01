# ecwcalc — ECW Expression Calculator (Go port)

A clean-room **Go** port of the **ECW Expression Calculator** (a legacy
Delphi 3-era Windows calculator by Alexey Torgashin / UVViewSoft), delivered
as both a **command-line tool** and a **faithful GUI** (IUP — native GTK on
Linux, Win32 on Windows, Cocoa on macOS).

The expression engine was reverse-engineered from the original binary
(parser, evaluator, operators, error messages, number formatting) and
verified **differentially against the FreePascal reference CLI** — the FPC
CLI itself is byte-exact 188/188 vs the original console engine running
under Wine. The Go battery scores **111/139 exact + 28 documented
last-ULP + 0 unexpected** (Go `float64` ≡ FPC `Double`; the 28 cases are
known single-ULP divergences carried over from the validated Rust engine).

## Contents

| Path | Description |
|---|---|
| `engine.go` | The expression engine (parser, evaluator, formatter) |
| `fmt.go` | Output formatting (bit-identical to the FPC CLI) |
| `cmd/ecw/main.go` | Command-line front end (FPC CLI interface, verbatim) |
| `gui/main.go` | IUP GUI — faithful reproduction of the original 4-form layout |
| `engine_test.go` | Unit tests |
| `battery_test.go` | Differential battery vs the FPC oracle (`ECW_FPC_BIN`) |

## Build — command line

Requires Go 1.22+.

```bash
go build ./cmd/ecw
./ecw "2+3*4"                        # 14
./ecw --unsigned "0xFFFFFFFF+1"      # 4294967296
./ecw --sep=1 "1,5+2,5"              # 4   (comma decimal / semicolon list)
./ecw                                # interactive, prompt '> '
```

## Build — GUI

Requires IUP GTK3 headers on Linux (`sudo apt install libgtk-3-dev`);
Windows and macOS need nothing (native Win32 / Cocoa).

```bash
CGO_ENABLED=1 go build -tags gtk3 -ldflags="-s -w" -o ecw-gui ./gui
./ecw-gui
```

## Test — differential battery

Run the battery against a compiled FPC reference CLI:

```bash
ECW_FPC_BIN=/tmp/ecw-oracle/ecw go test -v -run Battery .
```

## Releases

Binaries are built by GitHub Actions on tag push (`v*`) or manual
dispatch, for Linux x64, Windows x64, and macOS arm64 — see
`.github/workflows/` (`ci.yml` builds + tests + battery, `release.yml`
builds the matrix and publishes assets).

## License

MIT — see [LICENSE](LICENSE). (IUP and iup-go are also MIT.)
