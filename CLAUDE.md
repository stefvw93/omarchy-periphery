# Periphery exposé: rules

An Omarchy shell plugin (Quickshell/QML) with a Hyprland Lua hook. [README.md](README.md) covers install, [SPEC.md](SPEC.md) the product behaviour and its ubiquitous language. These rules are not final: they grow with every new pattern, library or edge case.

## Meta-rules

- Discuss new rules and rule changes Q&A style: ask one question, wait for the answer, then the next.
- When a rule here and the code disagree, stop and ask which one is right.

## Architecture

Three layers, each with one job:

| Layer    | Where                        | Does                                                                                                                                       |
| -------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Logic    | `src/<module>/` (TypeScript) | Pure functions: layout, navigation, string building, parsing. No Qt, Quickshell, Hyprland or `hl`. Everything testable lives here.         |
| Shell    | `plugin/*.qml`               | State, layer surfaces, animations, input, and the wiring between Hyprland and the logic. Imports the logic as `import "lib/<module>.mjs"`. |
| Hyprland | `plugin/hypr.lua`            | The hook loaded by `~/.config/hypr/hyprland.lua`: wraps actions, holds the selection state Hyprland needs.                                 |

- New logic goes in `src/`, not in QML functions. When QML code grows a decision or a computation, move it to `src/` first.
- `plugin/` is what ships: `vp run deploy` copies it to `~/.config/omarchy/plugins/stef.periphery/`. That folder is not a repo. Never edit it: the shell reloads plugins on any write under `~/.config/omarchy/plugins/`.
- `plugin/lib/*.mjs` is `vp pack` output. Never edit it by hand; commit it with the `src/` change that produced it.
- Quickshell's QML engine runs ES2017 plus some later syntax, not all: object spread/rest fails there. `vp pack` targets es2017; `scripts/bundle-check.sh` loads every bundle in the real engine.

## Workflow per change

In this order. Don't skip a step; say so if a step doesn't apply.

1. **Spec.** Discuss the change, then update the module's `src/<module>/specs.md` (and SPEC.md for product behaviour). Plain English, short sentences, SPEC.md's terms.
2. **Declare.** Write the API surface in `src/<module>/<module>.ts` with `declare` (types and signatures, no bodies).
3. **Test.** Write tests in `<module>.test.ts` against the spec, not against the code. Run them: they must fail.
4. **Implement.** Replace the `declare`s until the tests pass. The signatures stay as declared; if they must change, go back to step 2.
5. **Validate.** `vp run verify` until clean.
6. **Wire and deploy.** Change the QML, `vp run deploy`, `omarchy restart shell`, toggle the mode (`omarchy-shell shell toggle stef.periphery '{}'`), then `vp run smoke`.
7. **Hand-check.** Hover, clicks, drags and keys can't be tested from here (below). Don't wait for them: carry on, and list them at the end of the report, saying exactly what to try and what should happen. Never claim they work.

When a test disagrees with the spec, fix the test. When the spec disagrees with what the user wants, stop and ask.

## Validation

`vp run verify` is the one command. It runs, in order:

| Step                      | Checks                                                     |
| ------------------------- | ---------------------------------------------------------- |
| `vp fmt --check`          | Oxfmt: TypeScript, Markdown, JSON.                         |
| `vp lint --deny-warnings` | Oxlint plus the TypeScript type check. Warnings fail.      |
| `vp test run`             | Vitest, `src/**/*.test.ts`.                                |
| `vp run pack:fresh`       | `plugin/lib/` matches a fresh `vp pack`.                   |
| `scripts/bundle-check.sh` | Every bundle loads in Quickshell's QML engine (offscreen). |
| `vp run qml`              | Qt 6 qmllint on `plugin/*.qml`. Report only, for now.      |
| `vp run lua`              | `luac -p` on the hook, then `tests/*.test.lua`.            |

The hooks enforce it: a Claude Code `Stop` hook runs `verify` and sends me back while it fails; the git `pre-commit` hook (`.vite-hooks/pre-commit`) runs `vp staged` and `verify`.

## Code style

- TypeScript: Oxfmt with no semicolons, double quotes, 2 spaces, 100 columns. `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`.
- QML: hand-formatted, no formatter. 2 spaces, no semicolons, compact one-line functions where they fit. Match the surrounding code.
- Lua: match `plugin/hypr.lua`.
- Comments say why, not what. Match the comment density of the file.

## Live testing limits

- Cursor warps (`hl.dsp.cursor.move`) give a surface only an _enter_; motion inside a surface is not delivered. Hover between cards can't be tested with warps.
- `wtype` key events don't trigger Hyprland binds here.
- `hyprctl eval` returns only "ok": read values back with `error(...)`.
- Allowed while testing: open throwaway windows, move windows, switch workspaces, move the cursor, restart the shell, toggle the mode, `hyprctl reload`. The user may be using the desktop at the same time, so keep it short and put things back.
- Never close a window I didn't open myself, above all the terminal running this session. Before any close, check the target address is a throwaway window.

## Git

- Commit on my own once a change is done and `vp run verify` is green: one commit per coherent change. Push only when the user asks.
- Message style as in the history: a short summary line, then a plain paragraph on what and why. No attribution lines.
- The branches compare two approaches (see SPEC.md); check which one is checked out before changing anything.
