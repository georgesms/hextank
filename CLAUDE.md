# Contributing to HexTank

This is the contributing guide for humans and for Claude. Read [README.md](README.md)
first: it has the rules of the game, the architecture and the roadmap.

## The two goals of this project

1. **Build a working Tank Tactics game on a hex board.**
2. **Learn Elixir while doing it.** The owner of this repo is learning the language
   **by reviewing**: Claude writes all the code, the human reads and reviews it.

Goal 2 shapes everything below: code should be **simple and readable before clever**.
When in doubt, write the version a beginner can follow, because a beginner has to
review it.

## Guidance for Claude

- Prefer the plain, idiomatic solution. No metaprogramming, no macros, no custom
  behaviours, no protocols unless there is a real need and it was discussed first.
- When you introduce an Elixir or OTP concept for the first time in the project
  (pattern matching in function heads, `with`, guards, GenServer, PubSub, ...), explain it
  briefly **in your reply**, not in long code comments.
- **Claude writes all the code; the human reviews it.** Follow the review workflow
  below. Introduce each OTP piece (GenServer, Registry, DynamicSupervisor, Agent,
  PubSub) with a short explanation of what it is and why it's used here.
- The one thing the human owns is **approving `priv/moderation/prohibited_words.txt`**
  (Phase 5). Claude may seed it from a public list, but must not type slurs itself,
  and the human reviews and approves the list.
- Be extra careful in Phase 3 (process lifecycle races, safe file writes) and point
  out anything the human should review closely.
- Rule questions the README doesn't answer are the human's to decide: ask, don't
  guess.
- Never deploy or run `fly` commands that change anything without the human's
  approval (see *Deployment rules*).
- Work in small steps that follow the roadmap phases. Finish and test one piece before
  starting the next.
- Don't add dependencies without asking. Phoenix, LiveView and what
  `mix phx.new --no-ecto --no-mailer` generates (including Gettext) should be enough.
  The one planned addition is `Req`, in Phase 6: Google login is written by hand with
  it, not with an auth library.
- Phoenix's generated `AGENTS.md` has the usage rules for Phoenix, LiveView and HEEx.
  Follow it too; where it conflicts with this file, this file wins.
- Respect the frugality rules below. If a feature seems to need a database, a job
  queue or a new always-running process, stop and discuss it first.
- Don't implement the "possible rule variants" from the README unless asked.
- Tick the roadmap checkboxes in README.md when a feature is done.
- Run `mix precommit` before saying something is finished.

## Review workflow

1. **One branch per phase**, e.g. `phase-2-game-rules`, created from an up-to-date
   `main`.
2. **Small commits**, one idea each, each passing `mix precommit`. A reviewer should be
   able to read the branch commit by commit.
3. **Push the branch** and give the human the GitHub compare link
   (`https://github.com/georgesms/hextank/compare/main...<branch>`) to open a pull
   request and review it there.
4. **With the link, write a review guide** in the reply:
   - what the phase does, in a few sentences;
   - the reading order: which file or commit first;
   - the Elixir and OTP ideas that appear for the first time, briefly explained;
   - the places that deserve the closest look (tricky logic, races, security);
   - any decision made on the human's behalf, so it can be overruled.
5. **Review comments are addressed with new commits** on the same branch (no force-push
   during review), then push again.
6. **The human merges** the pull request on GitHub. Claude never pushes to `main` directly
   once the phase workflow is in use, and never merges.
7. After the merge: `git switch main && git pull`, then start the next phase.

## Commands

```bash
mix setup          # install deps and build assets
mix phx.server     # run the app at http://localhost:4000
iex -S mix phx.server   # same, with an interactive shell
mix test           # all tests
mix test test/hextank/hex_test.exs:42   # one test
mix format         # format the code
mix precommit      # compile with warnings as errors, format, test
mix gettext.extract --merge   # update translation files after changing texts
```

Erlang and Elixir versions are pinned in `mise.toml`. For Google login in
development, the client id and secret live in an uncommitted `.env`.

## Project layout

```
lib/hextank/hex.ex            cube coordinate math (pure)
lib/hextank/board.ex          radius and obstacles (pure)
lib/hextank/tank.ex           tank struct (pure)
lib/hextank/game.ex           game state and rules (pure)
lib/hextank/player.ex         player struct and strike rules (pure)
lib/hextank/moderation.ex     prohibited-word check (pure)
lib/hextank/storage.ex        all file reads and writes
lib/hextank/chat.ex           append, read and broadcast chat messages
lib/hextank/players.ex        load/save players, Google lookup, rejoin links
lib/hextank/players/bans.ex   Agent with banned player ids and Google accounts
lib/hextank/tables.ex         public API used by the web layer
lib/hextank/tables/table.ex   GenServer, one per active table
lib/hextank/tables/lobby.ex   GenServer with a summary of every table, cleanup
lib/hextank_web/live/         LiveViews (lobby, table, account)
lib/hextank_web/controllers/  dormant pages, rejoin links, Google login
priv/moderation/prohibited_words.txt   the word list (approved by the human)
priv/gettext/pt_BR/           Portuguese translations
rel/vm.args.eex               BEAM flags for one shared vCPU
test/hextank/                 tests mirror lib/
```

Runtime data lives under the `:data_dir` config (`priv/data` in dev, a tmp dir in
test, the Fly volume in prod). Never commit it.

```
data/tables/<id>/{game.bin, chat.jsonl, reads.bin}
data/players/<player_id>.bin
data/google/<sub>             contains the linked player_id
```

## Architecture rules

**Functional core, thin process shell.**

- `Hex`, `Board`, `Tank`, `Game`, `Player` and `Moderation` are **pure**: they take
  data and return data. No
  GenServer calls, no PubSub, no file access, no `DateTime.utc_now/0` inside them.
- Time comes in as an argument: `Game.start(game, now)`, `Game.catch_up(game, now)`.
  Only the process layer reads the clock.
- Randomness in the core must be controllable in tests: pass a seed or the chosen
  positions as an argument instead of calling `:rand` deep inside a function.
- The `Table` GenServer only: loads, calls `Game`, saves, sets timers, broadcasts, stops
  when idle. **No game rules in the GenServer.**
- All runtime file access goes through `Hextank.Storage`. Nothing else touches `File`.
  (The one exception: `Moderation` reads its word list at compile time.)
- Chat is not game state: it never goes into `%Game{}`.
- LiveViews only: render state and forward player intents to `Hextank.Tables`.
  **No game rules in LiveViews.**
- Never trust the browser. Every action is validated in `Game`, even if the UI
  already hides invalid options.

## Identity, security and moderation rules

- A player is whoever the session's `player_id` says. Never identify a player by
  nickname.
- The session cookie lasts 1 year (`max_age` set in the endpoint's session options).
- Rejoin tokens are passwords: never log them, never put them in PubSub messages,
  assigns sent to other players, or error messages.
- Google login: generate and check `state`; check `aud` (our client id) and `iss`
  (Google); request only the `openid` scope; store only `sub`. Tests use `Req.Test`
  stubs, never the real Google.
- **Every text a player writes goes through `Moderation.check/2` before it is saved or
  broadcast:** chat, private messages, nicknames, table names. Add the check to any
  new text input.
- Checking bans reads the `Bans` Agent, never the disk. A ban broadcasts on
  `"player:<id>"`, and every LiveView of that player handles it by leaving.
- **Never write real slurs in code, tests or replies.** Tests pass their own harmless
  list to `Moderation.check/2` (e.g. `["badword"]`). `prohibited_words.txt`
  changes only with the human's approval.
- Unbanning or clearing strikes happens only when the human asks.

## Translations

- All text shown to players goes through Gettext (`gettext("...")` in templates and
  LiveViews), with English as the source language.
- After changing texts, run `mix gettext.extract --merge` and fill in the pt-BR
  translations. Tell the human which ones are new so they can review the Portuguese.
- Error reasons (`:not_enough_ap`, ...) are translated in one place in the web layer,
  never in the core.

## Frugality rules

Target: ~1000 tables and a few hundred players online on one `shared-cpu-1x` 256 MB
machine that scales to zero. The README's *Frugality* section explains why; these are
the rules that follow from it.

- **No database.** Games are `term_to_binary` files, chat is append-only JSON lines
  (built-in `JSON` module). Write whole files via temp file + `File.rename/2`.
- **No always-running processes per table.** A `Table` GenServer runs only while the
  table is in use and stops itself after a few idle minutes. Missed ticks are applied
  with `Game.catch_up/2` on start. Never add a global scheduler or job queue for ticks.
- **Nothing reads all tables.** The lobby reads the `Lobby` GenServer's summaries; only
  boot scans the data folder.
- **Store the minimum.** No derived data in `%Game{}` (board cells are recomputed from
  the radius), event log capped at ~50 entries, chat history read as the last ~100
  lines.
- **LiveView assigns stay small.**
  - The static board is its own component, rendered once.
  - Tanks use a keyed comprehension.
  - Chat and event lists use `stream/3`.
  - Don't copy the whole game into assigns if the page only needs part of it.
- **No Presence**, no polling from the browser, no JS framework. Add a JS hook only
  when LiveView really can't do it.
- **Production:** `mix release`, the flags in `rel/vm.args.eex`, no periodic telemetry,
  log level `:warning`.
- When a change affects memory or CPU per table or per player, say so in your reply
  and, if unsure, measure it with LiveDashboard (`/dev/dashboard`).

## Deployment rules

We deploy to Fly.io. The plan, `fly.toml` and commands are in the README's
*Deployment* section.

- **Ask first, every time**, before any `fly` command that changes something:
  `deploy`, `launch`, `scale`, `secrets set`, `volumes create`, `machine` changes,
  `certs add`. One approval covers one command, not the rest of the session.
- **Allowed without asking** (read-only): `fly status`, `fly logs`, `fly releases`,
  `fly volumes list`, `fly volumes snapshots list`, and `fly ssh console` for
  reading data or IEx inspection.
- **Never**: `fly apps destroy`, `fly volumes destroy`, or deleting anything under
  `/data`. If one of these seems necessary, explain why and let the human run it.
- Run `mix precommit` before every deploy. Don't deploy a red build.
- **Exactly one machine.** Always deploy with `--ha=false`; never scale above 1. The
  game files live on one volume.
- **Save format compatibility.** `Storage` writes `{version, data}`. When a change
  alters the shape of `%Game{}` (or any saved data), bump the version and add a clause
  that upgrades the old shape on load, with a test that loads an old-format file.
  A deploy must never make existing games unreadable.
- Before a deploy that changes the save format, take a backup
  (`fly ssh console -C "tar czf - /data" > backup-<date>.tgz`) and tell the human.
- After each deploy, check `fly status` and `fly logs` and say what you saw.
- Keep the dormant view working: it's what lets the machine scale to zero.
  - Every LiveView page must have the idle timers (hidden 5 min, no input 30 min)
    that send the browser to its dormant page.
  - Dormant pages are plain controller pages with a layout that doesn't load
    `app.js`, and they read only the `Lobby` summary. Never start a table process or
    open a websocket from them.
  - When adding a new LiveView page, give it a dormant page too, and test that the
    dormant page renders without starting the table.

## Hex grid conventions

We follow <https://www.redblobgames.com/grids/hexagons/> exactly. Use its names so the
code can be read side by side with the guide.

- Coordinates are **cube**: `%Hex{q: q, r: r, s: s}` with `q + r + s == 0`.
- **Always use all three coordinates, explicitly.** Never drop `s` because it can be
  computed from `q` and `r`, and never abbreviate. This applies to code, `@doc`s,
  doctests, tests, comments, commit messages and replies.
  - Build hexes with `Hex.new(q, r, s)`. It checks `q + r + s == 0` and raises
    `ArgumentError` otherwise (a wrong hex is a bug, not a game error). Never build
    the struct by hand.
  - Write examples as `Hex.new(1, -1, 0)` or `(q: 1, r: -1, s: 0)`, never `(1, -1)`.
  - Functions do the arithmetic on all three: `add/2` adds `q`, `r` **and** `s`.
- Orientation is **pointy-top**.
- The board is a **hexagon of radius `N`** around `Hex.new(0, 0, 0)`.
- Distance between hexes `a` and `b`:
  `max(abs(a.q - b.q), abs(a.r - b.r), abs(a.s - b.s))`.
- Directions, in this order (index 0..5), written as `{q, r, s}`:
  `{+1, 0, -1}, {+1, -1, 0}, {0, -1, +1}, {-1, 0, +1}, {-1, +1, 0}, {0, +1, -1}`.
- Hex to pixel, pointy-top, for cell `size`:
  `x = size * (sqrt(3) * q + sqrt(3) / 2 * r)`, `y = size * (3 / 2 * r)`.
  This is the guide's formula; `s` does not appear in it, but the function still takes
  a full `%Hex{q, r, s}`.
- Corner `i` (0..5) of a pointy-top hex is at angle `60 * i - 30` degrees.
- Clicks use `phx-click` with `phx-value-q`, `phx-value-r` and `phx-value-s` on each
  SVG polygon, so we don't need pixel-to-hex conversion. The LiveView rebuilds the
  hex with `Hex.new(q, r, s)`. A tampered click with `q + r + s != 0` raises and only
  crashes that player's LiveView, which reconnects. That's fine.
- When a function implements a formula from the guide, add a one-line comment with the
  section name (e.g. `# redblobgames: "Distances"`).

## Elixir style

- `mix format` is the law. Don't argue with it.
- Small functions with clear names. Prefer several function clauses with pattern
  matching over `if`/`cond` chains.
- Use the pipe `|>` when it reads top to bottom as a story; don't force it.
- Use `with` to chain steps that can fail. Rule checks return `:ok` or
  `{:error, reason}`, actions return `{:ok, game}` or `{:error, reason}`.
- Error reasons are atoms that read well in the UI: `:not_enough_ap`, `:out_of_range`,
  `:cell_occupied`. (There are no turns: anyone can act at any time with their AP.)
- Structs for domain data (`%Hex{}`, `%Tank{}`, `%Game{}`), plain maps for everything
  else.
- Every public function in the core has a `@doc`. Add a `@spec` for the core modules.
- Comments explain **why**, not what. The code says what.
- No `!` functions that raise for expected game errors; raising is for bugs.

## Testing

- The pure core is where most tests go. They are fast, need no setup and are
  `async: true`.
- `Hextank.Hex` uses **doctests** (`doctest Hextank.Hex`): examples in `@doc` double as
  documentation and tests. Check them against the guide's examples.
- `Hextank.Game`: one `describe` block per action, covering the success case and
  **every** error case.
- Build test games with small helper functions (a tiny board, tanks at known
  positions), not with randomness.
- `Game.catch_up/2`: test zero, one and many missed ticks, and a ghost that must not
  collect more than one vote.
- `Storage`: use a fresh tmp dir per test (ExUnit's `@tag :tmp_dir`), never the dev
  data folder.
- `Table` GenServer: a few tests for the wiring (start, act, broadcast, tick, save,
  stop when idle, reload and catch up). Use a very short tick interval and idle
  timeout, or send the messages directly.
- `Moderation`: normalization cases (case, accents, letter swaps, repeated letters),
  whole-word matching (an innocent word containing a listed one passes).
- `Player`: strike 1 and 2 warn, strike 3 bans.
- LiveView: a few `Phoenix.LiveViewTest` tests for the main flows (join, move, shoot,
  chat). Include ones that check:
  - a private message never reaches a third player;
  - a ban closes every open page of that player;
  - a rejoin link logs in on a fresh session, and a reset link stops working;
  - the dormant page renders without starting the table.

## Git

- Small commits, one idea each, in English, imperative mood:
  `Add hex distance`, `Validate range when shooting`.
- Keep the build green: `mix precommit` passes on every commit.
