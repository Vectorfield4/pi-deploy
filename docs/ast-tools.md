# AST tools

The `pi-tree-sitter` extension (npm:pi-tree-sitter) adds a write-time syntax
guard and five structural tools. Tools parse with tree-sitter on demand; no
cache.

## Tools

| Tool | Purpose |
|------|---------|
| `list_symbols(path?, kind?)` | Symbol inventory for a file or the project |
| `find_definition(name)` | Definition site of a symbol across the project |
| `find_callers(name, path?)` | Call sites; excludes the definition |
| `find_callees(path, name)` | Symbols a symbol calls, line per entry |
| `get_symbol_body(path, name)` | Source of a single symbol |

`list_symbols` replaces grep for structural questions. `get_symbol_body`
replaces `read` when one symbol is the target. `find_definition` /
`find_callers` / `find_callees` cover impact before a change.

## Write-time guard

The extension hooks `write` and `edit` globally. Content is parsed before it
hits disk; `ERROR` or `MISSING` nodes block the tool with a line, column, and
snippet. The agent sees the failure in the same turn and self-corrects. Edits
run in memory first, so the guard checks exactly what would be written. For
languages without a WASM grammar, a delimiter-balance scanner validates.

## Agent wiring

| Agent | Tools added | Use |
|-------|-------------|-----|
| `coder` | all five | `get_symbol_body` for the target function, `find_callers` before a signature change |
| `frontend-implementer` | all five | `list_symbols` for existing patterns, `get_symbol_body` for the component to extend |
| `frontend-architect` | all five | `list_symbols` over raw scans; `find_callers` for shared-type impact |
| `reviewer` | all five | `find_callers` / `find_callees` to verify impact claims in complex tasks |
| `orchestrator`, `qa`, `drawer` | none | no code reads; two of them cannot write code |

## Flow effects

- Syntax gate moves from review to write time. The reviewer no longer scores
  broken syntax; it scores semantics.
- Refactoring sub-tasks read the target symbol, not the file. Larger files
  cost one function instead of the whole body.
- Complex frontend work: the architect maps shared components without reading
  them, and routes impact through `find_callers`.

## Coverage

21 languages with symbol extraction (TS/JS/TSX, Python, Rust, Go, Java,
C#, Kotlin, Ruby, PHP, Dart, C, C++, Bash, ...), plus validation-only
grammars (JSON, YAML, HTML, CSS, TOML, Vue). The codebase stacks (TS/JS
frontend, Node/Python backend) are covered.

## Caveats

- Grammar WASM files come from jsDelivr CDN on first use, cached 30 days with
  ETag checks. The container's HTTP_PROXY / NO_PROXY must let the fetch
  through.
- EPL-2.0. Installing unmodified is fine; a forked patch must publish its
  diff.
- Unsupported languages fall back to a delimiter-balance scan, weaker than a
  parse.