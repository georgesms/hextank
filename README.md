# HexTank

A web version of **Tank Tactics** (originally *Tank Turn Tactics*, designed by Luke
Muscat at Halfbrick Studios), played on a **pointy-top hexagonal board**.

Built with Elixir, Phoenix and LiveView. Players join a **table** (one game room), get a
tank somewhere on the board, and slowly earn Action Points over real time. The fun is in
the diplomacy, alliances and betrayals as much as the tactics.

> Hex grid math follows Red Blob Games' guide:
> <https://www.redblobgames.com/grids/hexagons/>

---

## Rules

### Setup

- **Board:** a hexagon-shaped map of pointy-top hex cells, with a few **obstacles**
  (rocks) that no tank can enter.
- **Board size:** grows with the number of players: at least 15 cells per player,
  radius at least 4 (2 players: 61 cells; 20 players: 331 cells). The creator can
  also pick a radius from 3 to 12, 14, 16 or 18 (1027 cells). About one cell in ten
  is an obstacle.
- **Starting position:** each player's tank is placed on a random free cell, at least
  3 steps from every other tank when the board has room, so nobody starts within
  reach of anyone.
- **Health:** each tank starts with **3 HP**. At 0 HP the tank is destroyed.
- **Range:** each tank starts with range **2**. Range is the
  [hex distance](https://www.redblobgames.com/grids/hexagons/#distances) between two
  cells, so "within range 2" means "at most 2 steps away". Upgrades stop at the
  table's **maximum range, 5** by default (the creator can pick 4, 5, 6, 8 or no
  limit). The original game had no maximum.
- **Action Points:** each tank starts with **0 AP**.

### Visibility (fog of war)

- A living tank **sees twice its range**: every cell at most `2 × range` steps away.
  Its player's board is zoomed in on that hexagon and follows the tank; everything
  else is fog, and says nothing about rocks or tanks.
- A tank **only drives where it can see**: the target and the whole path must be in
  sight, so the cost of a path never gives away a hidden rock or tank.
- **Ghosts see the whole board.** Before the start and once the game is over, so does
  everyone.
- Someone who **isn't playing sees nothing** until the game is over, so nobody can
  spy on the board with a second player.
- Nothing hidden ever leaves the server: cells, tanks and animations in the fog
  aren't sent to the browser at all.

### Action Points (AP)

- Every **tick** every living tank gets **1 AP**. The table's creator picks the tick:
  10 seconds, 1 minute, 1 hour, 8 hours or 24 hours (the default).
- AP can be saved for later. There is no cap.
- Every action costs **1 AP** (driving: 1 AP per cell):

| Action          | Effect                                                                   |
| --------------- | ------------------------------------------------------------------------ |
| **Move**        | Drive to a free cell along the shortest path around rocks and tanks, **1 AP per cell**. |
| **Shoot**       | Deal **1 damage** to any tank within your range. Always hits.            |
| **Upgrade**     | Increase your range by +1, permanently, up to the maximum range.        |
| **Give AP**     | Give 1 of your AP to any tank within your range.                         |

### Controls

| On the board | Click | Second click / double-click |
| --- | --- | --- |
| An empty cell | Highlights the shortest path and its cost | Drives there |
| Another tank | Says whether it's within your range | Shoots it, or gives it 1 AP (if in range) |
| Your own tank | Highlights your range | Range +1 |

Hovering a tank shows its stats as emojis: ❤️ HP, ⚡ AP and 🎯 range, repeated up to
4 times and then counted (`7 × ⚡`); the panel and the player list show them the same
way. A bar above the board explains the
current selection. The **Your tank** panel always shows every action as a button
(**Move here**, **Shoot**, **Give 1 AP**, **Range +1**), enabled when it fits the
selection, which is handy on touch screens. It also has a switch that picks what a
double-click on another tank does: shoot it (the default) or give it 1 AP. Escape
cancels.

The board is a dark screen, the same in both themes ("Sala de Guerra", a war room's
map table). Each tank is the NATO symbol for armour in its player's neon colour: the
hull (a rectangle) points the way the tank last drove, the turret (an ellipse with
its gun) at the last tank it shot.

Every action shows a short animation on everyone's board: a move drives along the
shortest path, cell by cell, turning the hull before each leg and leaving two tread
marks that fade; a shot turns the turret, then fires a tracer with a burst (bigger
when a tank is destroyed); a ⚡ flies to the tank that got AP (dropping from above
for a ghost's vote) and a ring grows to the new range. When the game ends, a banner above the board names the winner ("You won!"
for them), and the winner's tank gets a crown. The animations are plain CSS, played
once when LiveView adds them to the page, and are turned off for people whose system
asks for reduced motion.

### Ghosts (eliminated players)

- A tank at 0 HP is removed from the board and its player becomes a **ghost**.
- Every tick, each ghost gets **one vote**. A ghost can spend it to give **1 AP** to any
  living tank, anywhere on the board, no range needed.
- Unused votes do not accumulate: a ghost has at most one vote at a time.
- This is what makes the game political: players you eliminate will spend the rest of
  the game feeding AP to your enemies.

### Victory

- The **last tank standing** wins.

### Details

- You can't shoot yourself or give AP to yourself.
- AP can only be given to living tanks. Ghosts vote only for living tanks.
- Range stops at the table's maximum range (5 unless the creator chose otherwise).
- Actions are resolved in the order they reach the table. Two players can never act
  "at the same time".
- Ticks are counted from the moment the game starts (a game started at 14:32 gets its
  AP every day at 14:32).

### Tables

- Anyone can create a table and chooses:
  - **public**: listed in the lobby, anyone can join;
  - **private**: not listed, joined only through the table's link (`/tables/<id>`).
    Table ids are random and unguessable, so the link itself is the invitation.
- A game needs **2 to 20 players**. The creator starts it; nobody can join after the
  start. Before the start, players can leave.
- A game is **finished** when only one tank is left. The table becomes **read-only**
  and is deleted **7 days** after the end.
- A table that never starts expires after **7 days**.
- A running table where **every living tank has more than 200 AP** counts as
  abandoned (nobody is spending AP any more) and is deleted. The check runs at boot
  and once a day, works out the AP of sleeping tables from the clock without waking
  them, and skips tables someone has open. With 1 AP every 10 seconds, 200 AP is
  about 33 minutes; with 1 per day, over 6 months.

---

## Hexagonal board

We use **cube coordinates** `{q, r, s}` with the constraint `q + r + s = 0`, exactly as
described by Red Blob Games. The board is a large hexagon of a given `radius` around
the origin `{0, 0, 0}`.

We always work with all three coordinates `q`, `r` and `s`, in the code and in the
docs, even though any one of them can be computed from the other two.

A radius-1 board has 7 cells. Written as `(q, r, s)`, pointy-top hexes sit in rows that
shift half a cell each:

```
           (0,-1,+1)   (+1,-1,0)
   (-1,0,+1)    (0,0,0)    (+1,0,-1)
           (-1,+1,0)   (0,+1,-1)
```

A board of radius `N` has `3N² + 3N + 1` cells (radius 5 → 91 cells).

The pieces of the guide we need, and where they go:

| Concept (guide section)            | Used for                                  |
| ---------------------------------- | ----------------------------------------- |
| Cube coordinates                   | Every position in the game                |
| Neighbors (6 directions)           | Movement                                  |
| Distances                          | Range checks for shoot / give AP          |
| Movement range / "range" (`N` steps) | Building the board, highlighting reach  |
| Rings / spirals                    | Optional: nicer spawn placement           |
| Hex to pixel (pointy-top)          | Drawing the board in SVG                  |

We draw each cell as an SVG `<polygon>` with `phx-click` and the cell's `q`, `r` and `s`
as values, so we never need *pixel to hex* conversion: the browser already tells us
which hex was clicked.

---

## Architecture

Kept deliberately small. Three layers, each only talking to the one below it, and plain
files on disk instead of a database:

```
 HextankWeb (LiveView)          renders the board and chat, sends player intents
        │
 Hextank.Tables (processes)     one GenServer per *active* table, timers, PubSub
        │                 │
        │           Hextank.Storage   game.bin + chat.jsonl per table, on disk
        │
 Hextank.Game  +  Hextank.Hex   pure functions, no processes, no disk, no clock
```

### Pure core (`lib/hextank/`)

- **`Hextank.Hex`** – a `%Hex{q, r, s}` struct and the math: `new/3`, `add/2`,
  `distance/2`, `neighbor/2`, `neighbors/1`, `range/2`, `ring/2`, `to_pixel/2`,
  `corners/2`.
- **`Hextank.Board`** – the board radius and a `MapSet` of obstacle hexes. The cells
  themselves are **not stored**: they are `Hex.range(Hex.new(0, 0, 0), radius)`.
- **`Hextank.Tank`** – `%Tank{player_id, name, seat, position, hp, ap, range,
  has_vote, frozen, heading, aim}`. A tank with 0 HP is a ghost. `heading` is the
  direction (0..5) of the last cell it drove to, `aim` its last target's position
  minus its own: the board draws the hull and turret from them.
- **`Hextank.Random`** – a shuffle that always gives the same order for the same seed,
  so randomness is repeatable in tests.
- **`Hextank.Game`** – the whole game state and the rules. Functions that change the
  game return `{:ok, game}` or `{:error, reason}`, and take `now` (and a `seed` where
  randomness is needed):
  - lobby: `new/1`, `add_player/4`, `remove_player/3`, `start/4`
  - `act/4` with one of `{:move, hex}`, `{:shoot, target_id}`, `:upgrade_range`,
    `{:give_ap, target_id}`, `{:vote, target_id}` (ghosts only); it also detects the
    winner
  - `tick/2` (hand out AP to the living and votes to ghosts), `catch_up/2` (apply
    every tick missed by `now`), `next_tick_at/1`
  - questions for the UI: `move_targets/2`, `tanks_in_range/2`, `tank_at/2`,
    `living_tanks/1`, `tanks_by_seat/1`

### Processes and storage (`lib/hextank/tables/`, `lib/hextank/storage.ex`)

- **`Hextank.Tables.Table`** – a GenServer holding one `%Game{}`. It only runs while
  the table is in use (see *Lazy ticks* below). It calls the pure functions, saves the
  game after every change, runs the tick timer while alive, and broadcasts on
  `Phoenix.PubSub`.
- **`Registry`** to find a running table by id, **`DynamicSupervisor`** to start
  tables on demand.
- **`Hextank.Tables.Lobby`** – a GenServer holding a small summary of every table
  (name, public or private, status, players), built from disk at boot and updated on
  every save. The lobby page reads this, so it never has to wake up or load 1000
  tables. It also deletes expired tables, at boot and once a day while running.
- **`Hextank.Storage`** – reads and writes the files of one table:
  - `data/tables/<id>/game.bin` – the `%Game{}` via `:erlang.term_to_binary/1`,
    rewritten on each change (write to a temp file, then rename, so a crash never
    leaves half a file).
  - `data/tables/<id>/chat.jsonl` – one JSON line per chat message, **append only**.
- **`Hextank.Chat`** – append and read chat messages (table chat and private
  messages) through `Storage`, broadcast them on PubSub. Chat is **not** part of
  `%Game{}`.
- **`Hextank.Tables`** – the public API the web layer uses (`create_table`, `join`,
  `act`, `subscribe`, `send_message`, ...).

### Players and moderation (`lib/hextank/players/`, `lib/hextank/moderation.ex`)

- **`Hextank.Player`** (pure) – `%Player{id, nickname, token_version, google_sub,
  strikes, banned_at}` and the strike rules (`add_strike/3`).
- **`Hextank.Players`** – create, load and rename players (`data/players/<id>.bin`),
  `screen/3` (moderation with strikes, used for every text a player writes), `ban/1`
  and `unban/1`. Later: look one up by Google account (`data/google/<sub>`).
- **`Hextank.Players.Bans`** – an `Agent` with the set of banned player ids, loaded at
  boot, so checking a ban never touches the disk.
- **`Hextank.Moderation`** (pure) – `check(text, words)` returns `:ok` or
  `{:error, {:prohibited, word}}`. The production word list is compiled into the
  module; `Hextank.Moderation.Text` does the normalizing.
- **`Hextank.Settings`** (pure) – table settings: defaults, allowed values, validation.
- **`Hextank.Chat`** – table chat and private messages, unread counts, the rate limit
  (see *Chat*).

### Web (`lib/hextank_web/`)

- **`LobbyLive`** – list public tables and your own tables, create one, join one.
  Each card shows the table's status: not started (players joined so far), running
  (tanks alive and destroyed, days since the start) or finished (the winner, days
  until it's deleted).
- **`TableLive`** – the board as inline SVG, the player's tank stats, the action
  buttons, a list of all players and ghosts, an event log, the chat.
- **`AccountLive`** – nickname, your rejoin link (copy, reset), your player id, Google
  login.
- **`AdminLive`** – statistics and bulk table deletion, for admins only (see *Admin
  page*).
- **`DormantController`** – static dormant pages (see *Deployment*).
- **`AuthController`** – rejoin links and the Google login redirect and callback.
- **Translations** – English in the templates, pt-BR in `priv/gettext/pt_BR`, chosen
  from the browser's language with a switch in the page header.

---

## Look

The look is called **Sala de Guerra** (war room): the map table of a cold-war
command centre. Military in the shapes, neon in the light.

- **Board:** a dark screen in both themes, hexes drawn as a thin grid, rocks hatched
  like impassable ground. Each tank is the NATO symbol for armour in its player's
  neon colour, with a short call sign above it.
- **Themes:** dark is the war room (blue-black panels, chalk text, cyan); light is a
  printed briefing map (bluish paper, ink, the same hues darker). Both have a faint
  plotting-table grid behind the page.
- **Type:** Saira Stencil One for titles, Share Tech Mono for labels and badges, the
  system font for running text. Both fonts are served by the app
  (`priv/static/fonts`, latin letters only, about 34 KB, SIL Open Font License).
- **Logo:** a hexagon drawn as a gun sight, with the armour symbol inside
  (`Layouts.hex_logo/1`, and `priv/static/favicon.svg`).

## Players, identity and moderation

### Identity: no accounts, optional Google

- **First visit:** you pick a nickname and get a random player id, stored in the
  session cookie (kept for 1 year after your last visit, not just until the browser
  closes).
- **Rejoin link:** the account page shows a personal link (`/rejoin/<token>`) with
  "bookmark this, it's your key", and the lobby reminds you it exists. Opening it on
  any device logs you back in as the same player, in every table.
  - The token is signed with `Phoenix.Token` and contains `{player_id, token_version}`,
    so nothing extra is stored. "Reset my link" bumps `token_version`, which makes
    old links stop working.
  - It works like a password: never logged, never shown to other players.
- **Login with Google (optional):** "Log in with Google" links your player to your
  Google account, so you can come back from any device without the link.
  - Plain OpenID Connect written by hand with `Req` (a small HTTP client, our one
    added dependency): no auth library, about 150 lines.
  - Asks only for the `openid` scope, so we get a stable Google id (`sub`) and **no
    email, no name, no photo**. We store only `sub → player_id`.
  - Checks: a random `state` in the session against login forgery; `aud` equals our
    client id; `iss` is Google. The ID token comes straight from Google's token
    endpoint over HTTPS, so OpenID Connect allows skipping its signature check.
  - Logging in with a Google account already linked to another player switches to
    that player. The previous identity is still reachable with its own rejoin link.

### Moderation: prohibited words, two warnings, then a ban

- **The list:** `priv/moderation/prohibited_words.txt`, one word per line, English and
  Portuguese, focused on **hate speech** (slurs, not general swearing). Written or
  seeded by the human, who approves every change. It's compiled into
  `Hextank.Moderation`
  (`@external_resource`), so checking costs no disk reads. Changing the list needs a
  deploy.
- **Portuguese forms:** each listed word also blocks its other gender (`-o`/`-a`),
  smaller and bigger forms (`-inho`/`-inha`, `-ão`/`-ona`) and every plural (`-s`,
  `-es`, `-ões`, `-ães`), so the list needs only one form per word. The forms are
  worked out while compiling (about 800 words, ~45 KB). Some forms are ordinary words
  (`bruxo` from `bruxa`): `priv/moderation/allowed_words.txt` lists them, and they are
  never blocked.
- **Normalizing before matching** (the same steps on the text and on the list):
  lowercase, remove accents (`ã` → `a`), undo common letter swaps (`4` → `a`, `3` → `e`,
  `0` → `o`, `1` → `i`, `@` → `a`, `$` → `s`), shorten repeated letters (`aaaa` → `a`).
  Then split into words and compare **whole words** only, so innocent words that
  contain a bad one are not blocked.
- **What is checked:** chat messages, private messages, nicknames, table names.
- **What happens:**
  - A text with a prohibited word is **not sent or saved**, and the player gets a
    strike.
  - Strike 1: "Warning 1 of 2".
  - Strike 2: "Final warning".
  - Strike 3: **ban**.
  - Strikes don't expire. Each strike records the time, the table and the matched word
    (not the whole message).
- **A banned player** can't create or join tables, act, chat or vote. All their open
  pages are closed at once (PubSub message on `"player:<id>"`). Their tank stays on the
  board, frozen: it can be shot but never acts again. If they linked Google, that
  Google account stays banned too.
- **Limits:** word lists are easy to get around and blind to context. An anonymous
  player can also come back as a new player. Google-linked bans stick; a later table
  option can require Google login.
- **Unban or clear strikes:** only by the human, from the remote IEx console
  (`Hextank.Players.unban(player_id)`). No admin page.

### Admin page

`/admin` is for the players listed in `ADMIN_PLAYER_IDS` (comma-separated player ids;
players see their id on the account page). Other players are sent back to the lobby,
and the check runs on every LiveView mount, not only in the router. For admins, the
header has an **Admin** link. The page has:

- **Statistics:** tables (waiting, running, finished, public, private), new tables per
  day for the last 14 days, players (registered, banned, at a table), actions used by
  kind, chat volume, and the server (table processes awake, BEAM memory).
- **All tables,** filterable by status, with checkboxes to **delete several at once**.
  A table is deleted inside its own process, so no action can save it again halfway;
  open pages of a deleted table go back to the lobby.

**What it stores: almost nothing.** Every number is worked out when the page opens or
**Refresh** is pressed, from what the app keeps anyway:

| Number | Comes from | Cost |
| --- | --- | --- |
| Tables, players at tables, new tables per day | `Lobby` summaries, already in memory | none |
| Actions by kind | `action_counts` in each `%Game{}` (a few integers), copied into the summary | ~100 bytes per table |
| Chat volume | the size of each `chat.jsonl` (`File.stat`, the file is never read) | one `stat` per table, only when the page opens |
| Registered and banned players | the players folder listing, the `Bans` Agent | one folder listing |
| Awake tables, memory | the `DynamicSupervisor`, `:erlang.memory/0` | none |

Left out on purpose, because they would need a new file written on every action or
message, or reading every chat: history over time (numbers cover the tables that
exist now; an expired table stops counting), messages counted one by one (the chat
volume is in bytes), and per-player activity.

### Other limits

- Nickname 2–20 characters, table name 3–40, chat message up to 500.
- Chat rate limit: 5 messages per 10 seconds per player.
- Times are shown relative ("next AP in 3 h 12 min"), computed on the server. No
  timezone database needed, and they work on the dormant pages too.

---

## Frugality

Target: **about 1000 tables and a few hundred players online at once on a single
`shared-cpu-1x` machine with 256 MB**, and the machine off when nobody is playing.
Every design choice below serves that target. Estimates, to be measured.

### Stack

- `mix phx.new hextank --no-ecto --no-mailer`: no database server, no connection
  pool, no mailer. Gettext stays for pt-BR; translations are compiled into modules, so
  they cost almost nothing at runtime.
- Games are files on a volume (`term_to_binary`), chat is append-only JSON lines (Elixir's
  built-in `JSON` module, no dependency).
- Nothing beyond what Phoenix and OTP give us: no Oban, Redis, Presence, clustering or
  JS framework. Registry, DynamicSupervisor, Agent, PubSub and `Process.send_after/3`
  are enough.
- Tailwind and esbuild run at build time only. `mix phx.digest` pre-compresses assets.

### Lazy ticks: sleeping tables

Tables don't need a process between visits. The AP ticks are computed from the clock:

1. Someone opens a table → `Hextank.Tables` starts its GenServer under the
   DynamicSupervisor, which loads `game.bin` and calls `Game.catch_up(game, now)`.
2. While players are on the page, the GenServer's timer runs `Game.tick/1` on time
   (needed for fast games, 10 seconds or 1 minute, where players watch AP arrive).
3. After a few minutes with no activity, the GenServer saves and **stops itself**
   (GenServer timeout). The table now costs zero memory and zero CPU.

The same `catch_up/2` also handles app restarts: there is only one code path.

### Scale to zero

Because nothing needs to run between visits, the Fly machine stops when idle
(`auto_stop_machines = "stop"`, `min_machines_running = 0`) and starts on the next
request in about 1–2 s. Game files survive on the volume.

### BEAM on one shared vCPU (`rel/vm.args.eex`)

```
+S 1:1 +SDcpu 1:1 +SDio 2                # one scheduler, few dirty schedulers
+sbwt none +sbwtdcpu none +sbwtdio none  # no busy-waiting, saves CPU credits
```

Plus: always run as a `mix release`, remove the periodic measurements from the
generated `telemetry.ex`, production log level `:warning`, a little swap
(`swap_size_mb`) as a safety net.

### Small data

- The board stores only its radius and obstacles; cells are recomputed.
- The game keeps only the last ~50 events.
- No statistics are stored, except a few action counters per game: the admin page
  works them out when it opens (see *Admin page*).
- LiveView:
  - the static board (cells, obstacles) is its own component, sent once and never again;
  - tanks are rendered with a keyed comprehension, so an action only sends the tanks that
    changed;
  - chat messages use `stream/3`, so the server forgets them after sending them to
    the browser;
  - LiveView processes hibernate when idle (the default, keep it).

### Chat

- **Live delivery** uses PubSub topics and doesn't need the table process:
  `"table:<id>:chat"` for table chat, `"table:<id>:player:<player_id>"` for private
  messages.
- **History** is the last ~100 lines of `chat.jsonl`. Private messages are in the same
  file with a `to` field and the server filters them, so a player never receives
  someone else's messages.
- **Unread counts**: a "last read at" per player, one small file per player
  (`data/tables/<id>/reads/<player_id>.bin`), so two players marking as read at the
  same time never overwrite each other, and chat state stays out of `%Game{}`.
- **Who can write**: the players of the table (ghosts too). Anyone watching reads the
  table chat.
- **Limits of the file approach:** no search, no direct messages outside tables, no
  global chat. If we ever want those, move to SQLite (still in the same machine). Only
  `Storage` and `Chat` change; the core stays the same.

---

## Deployment (Fly.io)

Why Fly.io: it is the cheapest host that fits this design (a persistent volume for the
game files, websockets, scale to zero), and nearly the whole deploy can be automated
from the terminal. Railway ($5 flat) is the fallback if Fly stops suiting us.

### Expected cost

| Item | Price | Notes |
| --- | --- | --- |
| `shared-cpu-1x` 256 MB machine | $1.94/month if always on | Less with scale to zero |
| 1 GB volume | $0.15/month | Billed even while the machine is stopped |
| Stopped machine root filesystem | ~$0.15/GB/month | Our image is small |
| Shared IPv4, HTTPS certificate | free | No dedicated IPv4 needed |
| Egress | $0.02/GB (NA/EU) | Tiny for a text-and-SVG game |

**Realistic total: about $0.50–2.50 per month.** No free tier: a card is required.
Check the billing page after the first month.

### Setup

| Setting | Value |
| --- | --- |
| App name | `hextank` (or the closest free name) |
| Region | `gru` (São Paulo), or whichever is closest to the players |
| Machines | **exactly one**. A volume belongs to one machine and our files can't be shared |
| Volume | `hextank_data`, 1 GB, mounted at `/data` |
| Environment | `DATA_DIR=/data`, `PHX_HOST=<app>.fly.dev`, `ADMIN_PLAYER_IDS=<your player id>` |
| Secrets | `SECRET_KEY_BASE`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (`fly secrets set`) |
| Snapshots | Fly's daily volume snapshots (kept 5 days by default) |

The heart of `fly.toml`:

```toml
app = "hextank"
primary_region = "gru"
swap_size_mb = 256

[env]
  PHX_HOST = "hextank.fly.dev"
  DATA_DIR = "/data"
  PORT = "8080"

[mounts]
  source = "hextank_data"
  destination = "/data"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

  [http_service.concurrency]
    type = "connections"
    soft_limit = 800
    hard_limit = 1000

[[vm]]
  size = "shared-cpu-1x"
  memory = "256mb"
```

Every open page keeps a websocket, so the proxy counts **connections**: Fly's default
(25 concurrent requests) would cap the game at about 25 players online.

### Things the app must do for this to work

- **Own its data volume without running as root.** Fly mounts the volume owned by
  root. The image's entrypoint (`rel/docker-entrypoint.sh`) hands `/data` to the
  `nobody` user, then starts the app as `nobody`.

- **Read `DATA_DIR`** in `config/runtime.exs` for `:data_dir`.
- **Stopping is always safe**, because every change is saved right away. When Fly stops
  the machine (idle, deploy, host move), nothing is lost. The release handles
  `SIGTERM` gracefully.
- **Inactive tabs go dormant** (see *Dormant view* below). Fly only stops the machine
  when there are no open connections, and a LiveView tab left open keeps its websocket
  open forever. Without this, one forgotten tab keeps the machine running all month.
- **Save format is versioned.** `Storage` writes `{version, game}`, so a deploy that
  changes `%Game{}` can still load files written by the previous version (see
  CLAUDE.md).

### Dormant view

An inactive table tab leaves the live table for a plain, static page, and comes back
with one click.

**When a tab goes dormant** (timers in `app.js`):

| Condition | Limit |
| --- | --- |
| Tab hidden (another tab, minimised) | 5 minutes |
| Tab visible but no click, key or scroll | 30 minutes (long enough to watch a 1-minute game) |

When a limit is reached, the browser goes to `/tables/:id/dormant`. That's a normal
page load, so the LiveView and its websocket close.

**The dormant page** (`DormantController`, not a LiveView):
- Shows the table name, "You've been away. The table keeps going: your tank still earns
  AP", and a big **Back to the table** button linking to `/tables/:id`.
- Reads only the `Lobby` summary. It doesn't start the table process or load
  `game.bin`, so opening it costs almost nothing.
- Uses a minimal layout **without `app.js`**: no LiveSocket, no websocket, nothing to
  keep the machine awake.
- Nothing is missed: when the player comes back, the table page loads fresh and
  `catch_up/2` has already applied every missed tick.

The lobby page gets the same treatment, with its own dormant page (`/dormant`)
linking back to `/`. The account and admin pages use that one too. Each LiveView
page names its dormant page in `data-dormant-url` on `<main>` (`Layouts.app/1`).

### Who does what

**Once, by the human (~15 minutes):**
1. Install `flyctl` (`curl -L https://fly.io/install.sh | sh`).
2. `fly auth signup` (or `fly auth login`) and add a card.
3. Choose the app name and region.
4. Approve the first deploy.

**Once, by the human, for Google login (~15 minutes):**
1. In the Google Cloud console, create a project and an OAuth consent screen
   (External, app name, support email, scope `openid` only).
2. Create an OAuth client of type "Web application" with these redirect URIs:
   `http://localhost:4000/auth/google/callback` and
   `https://<app>.fly.dev/auth/google/callback`.
3. Publish the consent screen. With only the `openid` scope, Google doesn't require
   an app review.
4. Put the client id and secret in a local, uncommitted `.env` for development. Claude
   runs `fly secrets set` for production, after approval.

**By Claude, from the terminal, once `flyctl` is logged in:**
1. `mix phx.gen.release --docker`: Dockerfile and release scripts.
2. `fly launch --no-deploy`, then edit `fly.toml` as above.
3. `fly volumes create hextank_data --size 1 --region gru`.
4. `fly deploy --ha=false` (**after the human approves**).
5. Check it: `fly status`, `fly logs`, open the URL, play a quick game.

**Every later deploy:** Claude runs `mix precommit`, then `fly deploy` after the human
says yes. Later, a GitHub Actions workflow can do it on every push to `main`
(`flyctl deploy --remote-only` with a `FLY_API_TOKEN` secret from
`fly tokens create deploy`). Then deploys need no one.

### Operating it

| Task | Command |
| --- | --- |
| Is it up? | `fly status` |
| What's happening? | `fly logs` |
| Inspect live tables | `fly ssh console`, then `/app/bin/hextank remote` for an IEx shell |
| Download a backup | `fly ssh console -C "tar czf - /data" > backup-$(date +%F).tgz` |
| Roll back | `fly releases`, then `fly deploy --image <previous image>` |
| Restore from a snapshot | `fly volumes snapshots list <volume id>`, then create a new volume from it |
| Unban a player (human only) | In the remote IEx shell: `Hextank.Players.unban("<player id>")` |

Fly's snapshots cover a lost volume. The occasional manual backup covers our own
mistakes, e.g. a bad deploy that corrupts game files.

---

## Feature roadmap

Each phase should end with something working and tested.

### Who writes what

The project is small (roughly 3,000–4,000 lines of Elixir and HEEx including tests).
**Claude writes all the code; the human learns Elixir by reviewing it.** Phases 2–4
were reviewed as pull requests; from Phase 5 on, work goes straight to `main` in small
commits, each step with a review guide: reading order, new Elixir ideas explained, and
the places that deserve the closest look (see CLAUDE.md, *Review workflow*).

| Phase | Written by | Effort | Confidence | Main risk | Human's part |
|---|---|---|---|---|---|
| 0 – Setup | Claude | Small | High | Erlang build on the machine; not overwriting our docs | Install system packages (done) |
| 1 – Hex math | Claude (done) | Small (~150 lines + doctests) | Very high | Almost none: fully specified by the guide | Read it; ask about anything unclear |
| 2 – Game rules | Claude | Small–medium (~400 lines + tests) | High | `catch_up/2` details: ghost votes not piling up, no ticks after game over, when each tick is due | Review; decide rule questions the README doesn't answer |
| 3 – Processes + storage | Claude | Medium | Medium–high | OTP races (an action arriving while an idle table stops), lobby summaries in sync, safe file writes, timer tests | Review carefully, following the review guide |
| 4 – Browser UI + identity | Claude | Medium | High for behaviour, medium for looks | Whether it looks good and feels nice to play, on a phone too | Playtest, review the Portuguese texts |
| 5 – Chat + moderation | Claude | Medium | High | Private-message leaks, ban reaching every open page (dedicated tests) | Review; approve the word list |
| 6 – Google login | Claude | Small–medium (~150 lines + tests) | High | Getting the OpenID Connect checks right (`state`, `aud`, `iss`) | Google Cloud console setup (~15 min) |
| 7 – Frugal deploy | Claude | Medium | Medium | Needs a Fly account and the `fly` commands; real numbers may differ from the estimates | Fly account, approve and run the deploy, check the load-test results |
| 8 – Nice to have | Decide per item | Varies | Varies | Web push is the hardest (keys, service worker) | Pick what's worth it |

### Phase 0 – Project setup
- [x] Erlang 29.1.1 and Elixir 1.20.4 with mise, pinned in `mise.toml`
- [x] `mix phx.new hextank --no-ecto --no-mailer` (Phoenix 1.8.15, LiveView 1.2),
      moved into place keeping our README.md and CLAUDE.md
- [x] Keep the generated `AGENTS.md` (Phoenix's usage rules); CLAUDE.md points to it
- [x] Removed `dns_cluster` (no clustering)
- [x] `git init`, `.gitignore` with `priv/data` and `.env`
- [x] `mix precommit` alias (generated by Phoenix 1.8)
- [x] `config :hextank, :data_dir` (`priv/data` in dev, `tmp/test_data` in test,
      `DATA_DIR` in prod)
- [x] pt-BR locale set up in gettext

### Phase 1 – Hex math (`Hextank.Hex`)
- [x] Cube coordinate struct `%Hex{q, r, s}`; `Hex.new(q, r, s)` rejects any
      `q + r + s != 0`
- [x] add / subtract / scale, the 6 directions, neighbors
- [x] distance
- [x] range (all hexes within `N`) and ring
- [x] pointy-top hex-to-pixel and hex corners for SVG
- [x] Doctests for every function, checked against the guide's examples

### Phase 2 – Game rules (`Hextank.Game`)
- [x] Board of radius `R` with random obstacles
- [x] Add and remove players in a lobby state (2–20), then start the game (random
      placement)
- [x] Move, shoot, upgrade range, give AP, with every rule from above validated,
      including the *Details*
- [x] Death turns a tank into a ghost
- [x] Tick: AP for the living, a vote for each ghost
- [x] `catch_up/2`: apply every tick missed since the last one, given `now`
- [x] Ghost vote
- [x] Winner detection, game over state
- [x] Event log capped at the last ~50 events
- [x] Unit tests for every rule and every error case

### Phase 3 – Tables as processes, saved on disk
- [x] `Storage`: save / load `game.bin` (temp file + rename)
- [x] `Table` GenServer: loads and catches up on start, saves after every change
- [x] Tick timer while alive, with a configurable interval (10 seconds to 24h)
- [x] Stops itself after a few idle minutes; started again on demand
- [x] Registry + DynamicSupervisor
- [x] `Lobby` GenServer with table summaries, built from disk at boot
- [x] Expired tables deleted (finished: 7 days, never started: 7 days)
- [x] PubSub broadcast of every state change

### Phase 4 – Playable in the browser, with identity
- [x] Players: nickname and random id in a 1-year session cookie, saved in
      `data/players/`
- [x] Rejoin link (`Phoenix.Token`) on the account page, with a reminder in the lobby;
      reset on the account page
- [x] Lobby: public tables and your tables; create public or private; the table's link
      is the invitation
- [x] Board rendered as SVG hexes: static board component + keyed tanks
- [x] Works on a phone: the board scales, cells are big enough to tap
- [x] Click your tank, see move targets and range highlighted
- [x] Action buttons, error flash messages
- [x] Ghost panel to cast the daily vote
- [x] Live updates for every player at the table
- [x] Event log ("Ana shot Bruno", "a ghost gave Carla 1 AP")
- [x] Relative times ("next AP in 3 h 12 min")
- [x] English and pt-BR texts, language from the browser, switch in the header

### Phase 5 – Chat and moderation (diplomacy is half the game)
- [x] Table chat: append to `chat.jsonl`, broadcast on PubSub, `stream/3` in the page
- [x] Private messages between players at the same table
- [x] History: the last ~100 messages on open
- [x] Unread counts, one last-read file per player
- [x] Length limits and chat rate limit
- [x] `Moderation.check/2` with normalization
- [x] Human: fill in and approve `prohibited_words.txt`
- [x] Moderation on chat, private messages, nicknames and table names
- [x] Strikes (warning, final warning, ban), `Bans` Agent, banned players' pages closed
      at once, frozen tanks

### Phase 6 – Google login (optional for players)
- [ ] Human: Google Cloud console setup (see *Deployment*)
- [ ] Add the `Req` dependency
- [ ] `/auth/google` redirect with `state`, callback exchanging the code with `Req`
- [ ] Check `state`, `aud` and `iss`; store only `sub → player_id`
- [ ] Link Google to the current player, or switch to the already linked player
- [ ] Banned Google accounts refused
- [ ] Tests with `Req.Test` stubs (never calling Google in tests)

### Phase 7 – Frugal deploy (see *Deployment*)
- [x] `mix phx.gen.release --docker`, with the `vm.args.eex` flags above
- [x] Trim `telemetry.ex`, production log level `:warning`; secure session cookie
- [x] `DATA_DIR` read in `runtime.exs`; save format versioned in `Storage`
- [x] Dormant view: idle timers in `app.js`, `DormantController` with a layout
      without `app.js`, for tables and the lobby (account and admin pages use the
      lobby's)
- [ ] Load test locally: 1000 tables, a few hundred LiveViews; measure with
      LiveDashboard and write the real numbers here
- [ ] Human: install `flyctl`, sign up, add a card, choose name and region
- [ ] `fly launch --no-deploy`, `fly.toml` as above, create the volume, set secrets
- [ ] First deploy (approved), check status, logs, play a game on the live URL
- [ ] Check scale to zero really happens (`fly status` after ~10 idle minutes)
- [ ] Later: GitHub Actions deploy on push to `main`

### Phase 8 – Nice to have
- [x] Table settings: board radius, tick interval, obstacle density, start HP/range
- [x] Board controls: click to preview, second click or double-click to act, multi-cell
      moves along the shortest path, stats on hover
- [x] Every action as a button in the tank panel; choose whether a double-click on
      another tank shoots it or gives it AP
- [x] Stats as emojis: ❤️ HP, ⚡ AP, 🎯 range
- [x] Light animations for moves, shots, AP gifts, range upgrades and the game's
      result (CSS only)
- [x] Fog of war: each tank sees twice its range, ghosts see everything; the camera
      zooms in on what you see, follows your tank and zooms out when your range grows
- [x] The "Sala de Guerra" look for every page: themes, stencil and monospace fonts,
      logo and favicon (see *Look*)
- [x] Board as a dark "war room" screen: neon armour symbols whose hull turns the way
      they drive and turret the way they aim; moves follow the shortest path with
      tread marks
- [x] Lobby cards show each table's status: players, tanks alive and destroyed, days
      since the start, the winner, days until deletion
- [x] Admin page: statistics computed on demand, bulk table deletion
- [ ] Table option "Google login required" (makes bans stick)
- [ ] Spectator mode
- [ ] Notifications (email or web push) – needs a mailer or a service worker
- [ ] SQLite, only if we want chat search or direct messages outside tables

### Possible rule variants (not planned, keep in mind)
- Obstacles block line of sight (would use the guide's *line drawing*)
- Spend 3 AP to heal 1 HP
- The killer takes the victim's remaining AP
- Ghost votes only count when 3+ ghosts vote for the same player (original jury rule)
- Hearts / AP pickups spawning on the board

---

## Development

```bash
mise install       # Erlang and Elixir, versions from mise.toml
mix setup          # install deps and build assets
mix phx.server     # run at http://localhost:4000
mix test           # run the tests
mix precommit      # format + warnings + tests, run before every commit
```

See [CLAUDE.md](CLAUDE.md) for the contributing guide.
