# Penalty Kings ⚽

A World Cup 2026 Roblox game: a **fan-festival shell wrapped around a 1v1 penalty-shootout PvP core**. Penalties are the sweet spot — unmistakably soccer, viral, and far easier to network than full-pitch play.

**Current state — Slice 5: monetization.** The full loop now earns. A **Store** sells a *2× Coins* gamepass (live ownership check → doubled match payouts) and **coin packs** as developer products, granted through an idempotent `ProcessReceipt` that records each `PurchaseId` in session-locked data so a retried receipt never double-grants. Asset IDs are placeholders in `Config.Monetization` until you create them on the Creator Dashboard — the store degrades to a "not set up yet" toast until then.

Built on: the **Fan Shop** (country-flag cosmetics, coin-priced) and **global leaderboards** (Most Wins / Most Coins via `OrderedDataStore`) from Slice 4.

Underneath: persistent profiles + match payouts (Slice 3), the matchmaking queue + best-of-5 state machine (Slice 2), and the single-player-vs-AI resolution (`Penalty.resolve`, Slice 1).

## Stack

| Tool | Role |
|------|------|
| [Rokit](https://github.com/rojo-rbx/rokit) | Toolchain manager (pins every tool below) |
| [Rojo](https://rojo.space) | Syncs `src/` into Roblox Studio |
| [Wally](https://wally.run) | Package manager (ProfileStore lands in Slice 3) |
| StyLua / selene | Formatting + linting |

All tool versions are pinned in [`rokit.toml`](rokit.toml). Run `rokit install` to fetch them.

## Project layout

```
src/
  shared/   ReplicatedStorage.Shared — config, net contract, types (both sides)
    Config.luau    every tunable in one place
    Net.luau       single source of truth for RemoteEvents
    Types.luau     the shape of data crossing the network
    Catalog.luau   the cosmetics shop menu + ownership helper
  server/   ServerScriptService.Server — AUTHORITATIVE
    init.server.luau   bootstrap: start data, route queue/submit remotes
    Matchmaking.luau   FIFO queue, pairs players, tracks live matches
    Match.luau         best-of-5 state machine: roles, timing, sudden death
    Penalty.luau       pure goal/save/miss resolution (PvP + AI keeper)
    DataService.luau   ProfileStore: load/save, leaderstats, coin payouts
    CosmeticsService.luau  shop: buy/equip validation + flag-above-head visual
    LeaderboardService.luau  global Most Wins / Most Coins (OrderedDataStore)
    MonetizationService.luau  gamepass perk + idempotent dev-product receipts
    ProfileStore.luau  vendored dependency (MadStudioRoblox/ProfileStore, MIT)
    ArenaService.luau  pool of per-match arenas (clones the template at offsets)
    World.luau         lighting + showcase stadium + arena-template geometry
  client/   StarterPlayerScripts.Client — input & feedback only
    init.client.luau   wires HUD <-> matchmaking + shop + store remotes
    UI.luau            lobby + match HUD + Shop / Ranks / Store panels + toasts
    ShotAnimator.luau  cosmetic ball/keeper tween for the server's result
    MenuCamera.luau    cinematic hero-shot camera for the lobby
    Sound.luau         2D SFX player (placeholder IDs skipped until set)
```

**Core principle:** the client *requests* a shot (zone + power); the **server decides** the outcome. The client never computes a goal. That boundary is the whole anti-cheat foundation.

## Run it in Studio

1. In Roblox Studio: **Plugins → Manage Plugins → install "Rojo"** (once).
2. From this folder, start the sync server:
   ```sh
   rojo serve
   ```
   (If `rojo` isn't on your PATH, prefix with `~/.rokit/bin/`.)
3. In Studio, open the **Rojo** plugin panel → **Connect**.
4. Press **Play**. Pick an aim zone, time the power bar, hit **SHOOT**.

Prefer a one-off place file instead of live sync?
```sh
rojo build -o PenaltyKings.rbxlx
```
Then open `PenaltyKings.rbxlx` in Studio.

### Testing PvP (two players)

Matchmaking needs two clients. In Studio: **Test tab → Clients and Servers →
set Players to 2 → Start**. Two client windows open; press **FIND MATCH** in
both to get paired into a shootout. (A solo player can still queue and will
simply wait for a second.)

### Persistence in Studio

ProfileStore needs DataStore access to persist between sessions. Turn on
**Game Settings → Security → Enable Studio Access to API Services** (and save
the place to Roblox once). Without it, ProfileStore runs in **mock mode**:
everything works in-session, but coins/stats reset when you stop the playtest.
Bump `PlayerData_v1` in [DataService.luau](src/server/DataService.luau) if you
ever change the profile schema in a breaking way.

The global leaderboards use `OrderedDataStore`, which also needs API access —
without it, every DataStore call is `pcall`-guarded and the boards simply show
"No entries yet" instead of erroring.

## Tuning

Almost everything that controls game feel — keeper difficulty, the power sweet
spot, rewards, goal size — lives in [`src/shared/Config.luau`](src/shared/Config.luau).
Change a number, re-sync, play. No gameplay code edits required.

## Checks

Run before committing — formats, lints, and **type-checks** the code:

```sh
./scripts/check.sh
```

The type-check (`luau-lsp analyze`) is the important one: it catches
`Vector3`/`CFrame` mix-ups, `nil` casts, and bad property types that formatting,
linting, and `rojo build` all miss. The vendored `ProfileStore` and `Packages`
are excluded. Type definitions are fetched automatically on first run.

## Roadmap

- **Slice 1 — Penalty core. ✅** Aim, power-bar timing, AI keeper, score.
- **Slice 2 — 1v1 PvP + matchmaking. ✅** Queue, alternate shooter/keeper, best-of-5, sudden death.
- **Slice 3 — Data & economy. ✅** ProfileStore (coins, win/loss, lifetime stats), match payouts, leaderstats.
- **Slice 4 — Festival shell.** Cosmetics shop ✅, global leaderboards ✅ (Most Wins / Most Coins). Still to add: lobby hub polish.
- **Slice 5 — Monetization. ✅** 2× Coins gamepass + coin-pack dev products (idempotent receipts). **SFX hooks ✅** (click / whistle / kick / goal / save / miss / purchase). Still to add: real sound + art assets, MeshPart swap, thumbnail/icon.

### Wiring up real purchases

The store is code-complete but ships with placeholder asset IDs. To go live:
1. On the **Creator Dashboard**, create a *2× Coins* **gamepass** and one
   **developer product** per coin pack.
2. Paste their IDs into `Monetization` in
   [Config.luau](src/shared/Config.luau) (`CoinDoublerGamepassId` and each
   pack's `productId`).
That's the only change needed — purchase prompts, the multiplier, and coin
granting are already wired.

### Adding sound

SFX are already hooked at every key moment (button clicks, the round whistle,
the kick, goal/save/miss stings, and purchase confirmations). They're silent
until you upload sounds and paste their IDs into `Sounds` in
[Config.luau](src/shared/Config.luau) — any left as `rbxassetid://0` are simply
skipped.

### Concurrency

Each match runs in **its own arena**, cloned from a shared template at a unique
offset by [ArenaService](src/server/ArenaService.luau) and released when the
match ends. Players are anchored at their arena for the duration and sent back
to the hub afterward. Many matches run side by side without sharing a ball.

### Map & art

The world is built in code with a **golden-hour stylized** look:
[World.setupLighting](src/server/World.luau) configures `Future` lighting + a
warm sun, `Atmosphere`, `ColorCorrection`, `Bloom`, `SunRays` and `DepthOfField`.
The arena is a stadium bowl under a bright, vivid match-day sky — striped turf +
box/arc markings, goal + translucent net, **packed multicolor crowd** filling
every tier (main + sides + corner infills), a **national-flag festoon** (banner +
overhead ring), a roofed canopy, players' tunnel, branded **jumbotron**,
floodlight towers and ad boards — and a **goal** triggers a confetti burst + net
ripple ([ShotAnimator](src/client/ShotAnimator.luau)). All built-in PBR materials.
The remaining lift to AAA is **premium MeshParts / PBR textures** (a hero
goal+net, stadium shell, custom skybox) dropped in over this.

Each stadium is ~1,100 parts (mostly crowd). Fine at low concurrency; a busy
public server wants the `StreamingEnabled` + mobile pass before launch.

**Cinematic menu.** The lobby is *not* a walkable space — it's a posed hero
shot. [World.buildShowcase](src/server/World.luau) builds a permanent stadium at
the origin, and [MenuCamera](src/client/MenuCamera.luau) locks a slow golden-hour
pan onto it behind a clean HUD. Players have no avatar at the menu
(`CharacterAutoLoads = false`); the [Match](src/server/Match.luau) spawns a
character at game start and removes it at the end.

A clean seam remains for the art pass:

- **Arena template** — replace the greybox `ServerStorage.ArenaTemplate` with a
  modeled stadium **in Studio**. The only contract: keep a `Ball` and `Keeper`
  part at their local positions, build the goal to `Config.Goal` dims (21×8,
  penalty spot 11 out), author it **facing −Z with the pivot at the goal-line
  center**. `ArenaService` clones whatever is there — no code change needed.
  (To version it in git, export to `ArenaTemplate.rbxmx` and map it in
  `default.project.json`.)
