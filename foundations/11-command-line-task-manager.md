# 11 — Command-Line Portfolio Task Manager

**Objective:** Organize engineering checklists in an isolated local workspace.

**Tech:** Python, argparse, SQLite.

## Key points

- **argparse mental model.** Subcommands (`add`, `list`, `done`) map to
  `add_subparsers()`; each gets its own args. Understand positional vs optional args,
  types, defaults, and how argparse generates `--help`. This is the standard, no-deps
  way to build a real CLI in Python.
- **Why SQLite (not a JSON file).** SQLite gives you ACID transactions, querying, and
  concurrency safety in a single file with zero server. Understand *when* a flat file is
  fine vs when you want a relational store (querying, relationships, integrity).
- **Schema & CRUD.** Tables, columns, primary keys; the four operations
  (Create/Read/Update/Delete) map to INSERT/SELECT/UPDATE/DELETE. Understand task
  *state* (todo/doing/done) modeled as a column.
- **Parameterized queries.** `cursor.execute("... WHERE id = ?", (id,))` — **never**
  string-format SQL. This prevents SQL injection and quoting bugs. A core habit.
- **Separation of concerns.** CLI parsing ≠ business logic ≠ data access. Keeping them
  separate is what makes it testable and extensible.

## When to use it

- A personal, offline, scriptable task tracker that lives in your terminal.
- Learning the CLI + relational-DB pattern that underlies countless real tools.

## Scenario

You track pre-deploy checklists across projects. `tasks add "rotate keys" --project api`,
`tasks list --status todo`, `tasks done 4`. It's fast, greppable, versionable, and works
offline — and querying "what's still open across all projects?" is one SELECT.

## Where AI misleads

- **String-formatted SQL (injection).** AI frequently writes `f"... WHERE id={id}"`,
  which is insecure and breaks on quotes. Insist on parameterized queries. Top trap.
- **No transactions / forgetting `commit()`.** AI's code may not commit, so changes
  vanish, or it doesn't handle partial failures.
- **Schema migrations ignored.** AI hardcodes `CREATE TABLE` with no "if not exists" or
  upgrade path; adding a column later breaks existing DBs.
- **argparse subcommand wiring.** AI often tangles `set_defaults(func=...)` dispatch or
  mishandles required subcommands, producing confusing errors.
- **Resource leaks.** Not using context managers (`with sqlite3.connect(...)`) leaves
  connections/files open.
- **Over-engineering.** AI may pull in an ORM or framework for what argparse + sqlite3
  (both stdlib) handle cleanly. Know when the simple tool is correct.
