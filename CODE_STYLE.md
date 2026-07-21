# CODE_STYLE.md — Writing Clean Code (guidance, not gates)

This is **advisory**. Unlike `CONVENTIONS.md` (structure + the CI-enforced 600-line cap), nothing here
is checked by a tool. These are principles to exercise judgment against — not rules to obey blindly.
When a principle and readability conflict, readability wins. Match the surrounding code.

Guiding idea: **optimize for the next person reading this** (often you, in three months, or an agent
with no memory of today). Clarity beats cleverness.

## Functions

- **One job.** A function should do one thing and its name should say what that is. If the name needs
  "and" (`validateAndSave`), it's probably two functions.
- **Short enough to see at once.** Aim to keep a function on one screen (~50 lines is a good gut check,
  not a limit). Long functions are usually several functions hiding together.
- **Few parameters.** More than ~3–4 is a smell — group related args into a small object / dataclass /
  model. Prefer named arguments when the call site would otherwise be ambiguous.
- **Return early (guard clauses).** Handle edge cases up front and return; don't wrap the happy path in
  deep `if` nesting. Flat reads better than nested.
- **Prefer pure functions.** Given the same input, same output, no side effects. Push I/O (DB, network,
  storage) to the edges; keep the core logic pure and easy to test. (This is why our backend keeps
  business rules in `service.py` and I/O in routers / `shared/storage.py`.)
- **No surprises.** A function shouldn't secretly mutate its arguments or reach into global state.

## Naming

- Name by **intent**, not type or mechanism: `activeStudents`, not `list2`; `canMessage`, not `check`.
- Booleans read as questions/states: `isVerified`, `hasJoined`, `allowMessages`.
- Avoid abbreviations and single letters (except tiny loop indices). Consistency > brevity.

## Duplication & abstraction

- **Don't repeat yourself** — but don't abstract prematurely either. The **rule of three**: two copies
  is fine; extract on the third, once the real shared shape is clear.
- A wrong abstraction costs more than a little duplication. Prefer clear duplication over a clever base
  class that couples unrelated things.

## Control flow & complexity

- Keep nesting shallow. Deep `if/for/if/try` is the real complexity — more than line count.
- One level of abstraction per function: don't mix high-level orchestration and low-level fiddling in
  the same body.
- Make illegal states hard to represent — lean on types/enums/models instead of runtime checks.

## Comments

- Explain **why**, not **what**. The code says what; a comment earns its place by explaining intent,
  a trade-off, or a non-obvious constraint.
- Delete dead code and stale comments — git remembers; the file shouldn't have to.

## Errors

- Fail loudly and early; don't swallow exceptions to make a symptom disappear.
- Handle errors at the layer that can actually do something about them (e.g. HTTP concerns in the
  router, not buried in a helper).

## Language notes

- **Python:** type hints on public functions; f-strings; prefer comprehensions when they stay readable;
  small dataclasses/Pydantic models over passing loose dicts around.
- **Dart/Flutter:** `const` constructors where possible; extract widgets rather than growing one
  `build`; keep state in providers, presentation in widgets; small, focused widgets compose better.

## The one test

Before you finish a function, ask: **"Could a teammate understand this without asking me?"** If not,
it's not the line count that's the problem — it's the clarity. Fix that.

See also: `CONVENTIONS.md` (structure + enforced rules).
