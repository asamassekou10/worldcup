# Penalty Kings — World Cup 2026
## Professional Game Improvement Plan
**Prepared:** 2026-06-13  
**Team:** Senior Roblox Dev · Map Builder · Game Designer  
**Tournament window:** June 11 – July 19, 2026 (Final at MetLife Stadium, NJ)  
**Our runway:** ~5 weeks of peak World Cup traffic

---

## 0. Competitive Landscape (Know Your Enemy)

The official **FIFA × Gamefam** event launched June 5 on Roblox — six games, 28 million sessions/week, all 48 national teams, live scores, exclusive rewards. FIFA Super Soccer alone has 1.1 billion visits.

**We cannot out-FIFA FIFA. We don't need to.**

Penalty Kings is a *specialist* game. Penalty shootouts decide knockout rounds — they are the single highest-drama moment in football. Every World Cup fan understands the penalty spot. Our job is to be the **deepest, most satisfying penalty experience on the platform**, not another full-pitch soccer game. This is our moat.

**Positioning:** *"FIFA shows you the World Cup. Penalty Kings puts you IN it."*

---

## 1. Vision Statement

Penalty Kings is a **World Cup fan hub** built around the penalty spot — a living stadium that evolves with the real tournament, packed with activities, social moments, and drama. Players represent their nation, earn a place in history, and experience the pressure of a World Cup final shootout from the boots of the player who steps up.

By the final whistle on July 19, Penalty Kings should feel like **the place Roblox World Cup fans go between matches**.

---

## 2. Core Identity Pillars

| Pillar | What it means in practice |
|--------|--------------------------|
| **Drama** | Every penalty kick must feel like a World Cup final. Camera, sound, crowd, slow-mo replay. |
| **Representation** | All 48 nations. Players feel proud to rep their country. Country leaderboards matter. |
| **Living World** | The hub updates with real tournament results. Group stage gives way to knockouts. |
| **Depth over Breadth** | More to do around the penalty spot, not a half-baked 11v11 mode nobody asked for. |
| **Social First** | Screenshots, rivalries, Watch Parties, country vs country moments that spread on social media. |

---

## 3. Phase Roadmap

### PHASE 1 — Foundation (Week 1 — NOW)
*Get the core working correctly. Already mostly done.*

- [x] Goal dimensions calibrated (13.2 × 5.7 studs, measured from actual posts)
- [x] Keeper marker hidden
- [x] Crowd boundary hardcoded to real turf measurement (72-stud half-width)
- [x] Aim zone base Y fixed (no longer floating above the goal)
- [ ] **Build the place and do a full playtest session** — shoot 20 penalties, verify aim zone, keeper reach, ball flight
- [ ] **Keeper glove cosmetics** — first monetisation hook; 3 variants (basic/gold/national)
- [ ] **Ball skin cosmetics** — 3 variants, one per host nation (USA stars, Mexico eagle, Canada maple)
- [ ] Fix `Config.Goal.PenaltySpotDistance` to match actual pitch (currently 11, actual ~20 studs)

---

### PHASE 2 — Tournament System (Week 1–2)
*Tie the game to the real World Cup bracket. This is the biggest retention lever we have.*

#### 2A. Live World Cup Bracket (Game Designer + Senior Dev)

The 2026 World Cup has:
- **48 teams**, 12 groups of 4, running June 11 – July 3
- **Round of 32** — June 28 – July 4
- **Round of 16, QF, SF** — July 4–15
- **Final** — July 19, MetLife Stadium, NJ

**Feature: The War Room**
A dedicated room in the hub displaying the real bracket. Each match result updates a physical scoreboard. When a real-world team gets eliminated, their section of the board goes dark. When a penalty shootout decides a match IRL, Penalty Kings lights up a special event mode.

Implementation:
```
- HttpService fetches from a free football-data API (e.g., api-football.com, football-data.org)
- Server-side DataStore caches results every 5 minutes (avoids API rate limits)
- Client reads from DataStore, not directly from API
- Fallback: manual admin-updateable table in Config.luau if API is unreliable
```

#### 2B. Nation Allegiance System (Game Designer)

When a player joins for the first time they pick their nation from all 48 teams. This is persistent (DataStore). Their nation flag appears above their head. They earn **Nation Points** for every goal scored, which feed a global per-nation leaderboard.

- Nation leaderboard visible in the hub at all times
- When a nation's real-world team gets knocked out, their players unlock a "defeated" emote and a badge ("Brave Nation")
- Final 2 nations standing at the game's real final get a special "Finalist" aura cosmetic (server-wide announcement)

#### 2C. Penalty Shootout Event Mode

When a real World Cup match goes to penalties IRL (tracked via API), the game triggers a **Penalty Night** server-wide event:
- Red flares and sirens in the hub
- A dedicated server opens: "World Cup Shootout — [TeamA] vs [TeamB]"
- Players can join as fans of either side and play their own parallel penalty duel
- Coins payout 3× during Penalty Night

---

### PHASE 3 — Minigames & Activities (Week 2–3)
*The hub must feel alive even when players aren't in a match. Target: 30+ minutes average session.*

#### 3A. Free Kick Challenge (Senior Dev + Game Designer)
A solo or co-op challenge at a wall of defenders. The ball curves over/around the wall into the top corner. Uses existing `ShotAnimator` curve system but with a defender wall obstacle at fixed positions. Three difficulty tiers: League, Champions, World Cup Final. Weekly best scores per tier → prizes.

#### 3B. Goalkeeper Gauntlet (Senior Dev)
Players ARE the keeper for 60 seconds. AI fires 10 rapid penalties from random positions (using existing `Penalty.resolveSkill` but with the shooter's x/y randomised). You must time your dive correctly. Scored on saves made. Unlocks "Golden Gloves" title cosmetic at 8+/10.

#### 3C. Juggling Pitch (Map Builder + Senior Dev)
A small grass area beside the main stadium. Players click/tap a button to kick the ball upward and count consecutive touches. Uses a simple physics ball with bounce detection. Leaderboard on a post beside the pitch. Badge at 50 touches: "Street Footballer."

#### 3D. World Cup Trivia Kiosk (Game Designer)
An NPC host beside the prediction kiosk in the existing hub. 5 multiple-choice questions about World Cup 2026, history, and host nations. 3 correct in a row → 25 coin reward. Refreshes daily. Easy to maintain via a `TriviaData` ModuleScript with question tables.

#### 3E. Penalty Walk-Off (Senior Dev)
Sudden-death variant of the main 1v1 mode. Both players score → next round, kick from 1 stud closer. Keeps going until someone misses. The psychology of an encroaching spot is completely different from standard penalties — new content with almost no new code. Accessible via a separate portal in the hub.

#### 3F. Watch Party Room (Map Builder)
A large tiered cinema-style room with a giant screen SurfaceGui showing:
- Current real-world scorelines (from the API)
- Group table standings
- Countdown to next match
- "Match of the Day" highlight quotes

Players can sit in seats beside other fans of their nation, chat, and watch the ticker together. Social glue — people stay in the game to see scores.

---

### PHASE 4 — Hub World Expansion (Week 2–4)
*The map must feel like you're actually AT the World Cup, not in a random stadium.*

#### 4A. The Fan Zones (Map Builder — primary deliverable)

Divide the hub's outer ring into **6 continental fan zones**, each with distinct architecture, colour palette, and ambient sounds:

| Zone | Nations | Visual Style | Ambient Sound |
|------|---------|-------------|---------------|
| **The Americas** | USA, Mexico, Canada, Brazil, Argentina, + | Mariachi colours, star-spangled, maple accents | Samba drums, crowd chanting |
| **Europe** | France, England, Germany, Spain, Portugal, + | Old-stadium brick, UEFA flags, cobblestones | European ultras chant |
| **Africa** | Morocco, Nigeria, Senegal, South Africa, + | Vivid prints, drums, bright textiles | Vuvuzelas, djembe |
| **Asia-Pacific** | Japan, South Korea, Australia, + | Neon accents, cherry blossoms, modern glass | Taiko drums |
| **CONCACAF** | Costa Rica, Panama, Jamaica, Honduras, + | Tropical colour, street art | Steel pan, reggaeton bass |
| **South America** | Colombia, Ecuador, Uruguay, Chile, + | Carnival flags, cobblestones, tango colours | Cumbia, ultras drums |

Each zone has:
- A **Fan Gate** — a cosmetic archway players walk through to enter
- **2–3 NPCs** in kit colours of zone nations
- A **mini trophy case** showing their nation's World Cup history (text SurfaceGui)
- A zone-specific **emote** unlockable by completing one minigame in that zone

#### 4B. The Trophy Room (Map Builder + Game Designer)
A grand circular chamber at the hub's centre, modelled on a real trophy hall. Displays:
- The FIFA World Cup trophy replica (spinning gold model)
- Historical winner plaques (SurfaceGui panels, 1930–2022)
- A **live "2026 Champions" plinth** — blank until July 19, when the winning nation's flag auto-populates
- Player's personal medal cabinet (DataStore-backed achievements displayed in 3D)

#### 4C. Stadium Upgrades (Map Builder)
The main stadium already has blocky crowd and floodlights. Upgrades:
- **Large LED scoreboard** above the goal (SurfaceGui, shows current match score or "Penalty Kings" between matches)
- **TV camera gantry** rigged from crossbar — decorative but adds realism
- **Substitution board** NPC beside the pitch who counts down match time
- **Dugout benches** on both sides with seated coaching staff NPCs
- **VAR room** behind the goal (glasswalled box with TV screens — decorative, but a photo moment)
- **Goal net physics** — netting parts that visually "billow" when a goal is scored (TweenService sine wave on net Parts)

#### 4D. Broadcast Booth (Map Builder + Senior Dev)
An elevated booth above the stand with two commentator NPCs. When a player scores:
- A `SoundService` voice line plays (pre-uploaded audio): "GOOOAL!" / "What a save!" / "The keeper had no chance!"
- The NPCs animate (simple wave/jump TweenService)
- A BillboardGui above the goal flashes the player's name

---

### PHASE 5 — Progression, Economy & Social (Week 3–5)
*Retention is built on progress loops. Players must always have something to work toward.*

#### 5A. Player Card System (Game Designer — hero feature)
Inspired by Panini World Cup stickers. Every player has a **Player Card** — a collectible visual identity card displayed in-game and in their profile.

Card tiers:
- **Bronze** — starter (free, earned at tutorial completion)
- **Silver** — earned at 50 goals scored
- **Gold** — earned at 200 goals scored
- **World Cup Icon** — earned at 500 goals OR by winning a Penalty Night event
- **Limited** — issued for real-world events (e.g., "Golden Boot Weekend" when top scorer is awarded IRL)

Cards show: username, nation flag, goals scored, saves made, win rate, favourite shot position (heatmap).

**Sticker Album:** A physical album NPC in the hub where players can "trade" duplicate cosmetics for sticker packs. The social interaction of "I need the Brazil Gold card" drives organic retention.

#### 5B. Season Pass — "The Road to the Final" (Game Designer + Senior Dev)
A 6-week (June 13 – July 19) free + premium battle pass tied to the real tournament.

**Free track (40 tiers):**
- Coins, XP boosts, standard emotes, basic ball skins

**Premium track (40 tiers, ~400 Robux):**
- Exclusive national kit ball skins for all 48 nations
- "Golden Boot" shooting trail (golden particle behind ball in flight)
- "Crowd Roar" celebration (players get a stadium-wide cheer effect on goal)
- World Cup Final Frame — exclusive Player Card border
- "Trophy Lift" emote (player raises a trophy model above their head)

Tiers progress via **Season XP**, earned from:
- Goals scored (10 XP), saves made (8 XP), daily login (25 XP), quest completions (50 XP), Penalty Night participation (100 XP)

At Tier 40 Premium: a permanent "World Cup Legend 2026" title badge — can't be earned after July 19.

#### 5C. Daily / Weekly Quest System (Senior Dev)
Rework the existing quest system:

**Daily (resets midnight UTC):**
- Score 5 goals → 50 coins
- Make 3 saves as keeper → 40 coins
- Play 3 matches → 30 coins
- Score with a curved shot → 25 coins
- Beat a player from a different continent → 45 coins

**Weekly (resets Monday):**
- Win 10 matches → 300 coins + 200 Season XP
- Score from a Walk-Off penalty → 150 coins + rare sticker pack
- Complete all daily quests 5 days → 500 coins + Premium Season XP boost
- Top your nation's weekly leaderboard → 1000 coins + "Captain's Armband" cosmetic (1 week)

**World Cup Milestone Quests (one-time):**
- Score 100 goals total → "Penalty Specialist" title
- Reach Round of 32 in the Tournament bracket → 500 coins
- Win a Penalty Night event → "Shootout Hero" Player Card border
- Log in during the World Cup Final (July 19) → "I Was There" badge

#### 5D. Nation vs Nation Global Leaderboard (Game Designer)
All 48 nations compete in a real-time goals tally. Displayed on a giant leaderboard screen in the hub. The top nation each week gets a **golden stadium light** effect on their Fan Zone gate.

When a nation's real team gets knocked out in the actual tournament:
- Their fans in-game get a commemorative "Fought With Pride" banner on their player card
- Their nation's goals in Penalty Kings are archived and celebrated ("Portugal fans scored 24,847 goals before elimination")
- This creates meaningful moments and keeps eliminated-nation players engaged

#### 5E. Social & Sharing Hooks
- **Photo Mode:** pause your character in a pose (celebration, goalkeeper dive, penalty run-up) and a clean UI overlay lets you screenshot for social media. Watermark: "Penalty Kings — World Cup 2026 | play.roblox.com"
- **Replay System:** after every goal, the ball flight is replayed from the TV cam angle with slow-mo in the final 0.5 seconds. Players can press a button to "Share Replay" (generates a shareable moment in the Roblox share system)
- **Rivalry System:** track your head-to-head record against specific players. A notification fires when a rival is online — "Your rival [name] just joined Penalty Kings"

---

### PHASE 6 — Polish, Audio & Visual Fidelity (Week 4–5)
*Professional games feel professional. This is what separates top-100 Roblox games from good ones.*

#### 6A. Audio (Senior Dev)
| Sound | Source | Priority |
|-------|--------|----------|
| Crowd chant reacts to shots (rises as ball hits net, groans on miss) | Upload custom audio | Critical |
| Commentator voice lines: GOAL, SAVE, MISS, PENALTY NIGHT | Upload 6–8 lines | Critical |
| Boot-on-ball leather kick sound (different from a miss) | Upload 2 variants | High |
| Net ripple sound (ball entering net) | Upload | High |
| Pre-match whistle + crowd hush | Existing asset `9125969478` | Done |
| National anthem snippet on match start (country vs country) | Upload 48 short clips | Stretch |
| Ambient fan zone audio (samba, drums, etc.) | Upload per zone | Medium |

The crowd audio must REACT: `SoundService` with a `Sound` whose `PlaybackSpeed` and `Volume` lerp upward when the ball is mid-flight and peaks on goal. This is one of the highest-impact single-feature improvements possible.

#### 6B. Visual Polish (Map Builder + Senior Dev)
- **Depth-of-field** on the keeper camera: background blurs when zoomed in on the shooter — dramatic
- **Ball shadow** during flight: a lerped Part on the ground tracking the ball's XZ position gives depth perception
- **Post-hit shake:** `Camera:GetCurrentCamera()` shake on GOAL (violent) and MISS (short shake), SAVE (medium)
- **Goal light burst:** when a goal is scored, a ring of `PointLight` instances in the net flares to max brightness and fades over 0.8s
- **Turf quality:** replace the current flat green with a two-tone stripe turf using decals or custom terrain — adds instant professionalism
- **Player character:** consider a custom R15 rig with goalkeeper gloves visible as accessories, and a proper boot mesh replacing default shoes

#### 6C. UI Overhaul (Senior Dev)
Current UI is functional. Upgrade to professional:
- **Main HUD**: dark translucent panel style (like EA FC / FIFA UI) with gold accents matching WC 2026 branding
- **Shot power bar**: animated fill with a pulsing sweet-spot indicator and an overshoot red zone
- **Aim reticle**: replace current reticle with a dynamic cursor that wobbles under pressure (increases wobble as match stakes rise — e.g., round of 32 vs group stage)
- **Match result screen**: full-screen cinematic overlay: nation flags, score, MVP (highest shot difficulty scored), "GOAL" / "SAVED" / "MISS" in large text with animation
- **Loading screen**: World Cup 2026 branded, with a random real WC stat or quote

#### 6D. Anti-Cheat & Fairness (Senior Dev)
With a live economy and leaderboards, cheating must be addressed before scale:
- Server-side shot resolution already exists (`Penalty.luau`) — good foundation
- Add: server-side cooldown between shots (minimum 2s between `ShotRequest` remote events)
- Add: server-side goal counter validation (can't earn more than ~180 goals/hour — physical impossibility)
- Add: DataStore write throttle — batch-write every 30s, not per-goal
- Add: ban list in a simple admin ModuleScript, checked on join

---

## 4. Technical Architecture Notes (Senior Dev)

### Multi-Place Setup
As the hub grows, split into two Roblox Places under one Universe:
- **Place 1: Hub World** — fan zones, trophy room, watch party, minigames, leaderboards
- **Place 2: Match Server** — the actual penalty pitch, stripped of all hub assets for performance

`TeleportService` moves players between places. This lets you run 50-player hub servers while keeping match servers lean (2 players).

### API Integration for Live Scores
```
HttpService (server-side only) → football-data.org or api-football.com
↓ (every 5 min via task.delay loop)
DataStore: "WC_Scores_2026" → store match results table
↓
ReplicatedStorage RemoteEvent "ScoreUpdate" → clients poll on join
↓
Watch Party screen SurfaceGui / War Room scoreboard
```
Use a free tier API (football-data.org offers 10 req/min free). Cache aggressively. Never call from client.

### DataStore Schema
```lua
-- Per player
{
    nation = "Brazil",
    goals = 0,
    saves = 0,
    wins = 0,
    level = 1,
    xp = 0,
    seasonXP = 0,
    seasonTier = 0,
    premiumPass = false,
    cosmetics = { balls = {}, emotes = {}, titles = {} },
    questProgress = { daily = {}, weekly = {}, milestone = {} },
    lastLogin = 0,
    loginStreak = 0,
    playerCard = { tier = "Bronze", border = "default" },
    headToHead = {},  -- { [userId] = { wins, losses } }
}

-- Per nation (global DataStore)
{
    totalGoals = 0,
    weeklyGoals = 0,
    memberCount = 0,
}
```

---

## 5. Monetization Strategy

Target: **200–400 Robux average revenue per paying user**. Keep the core game fully free.

| Product | Price | Description |
|---------|-------|-------------|
| **Premium Season Pass** | 399 R$ | Unlock premium track of "Road to the Final" battle pass |
| **Coin Doubler Gamepass** | 299 R$ | 2× coins from all sources, permanent |
| **National Kit Bundle** | 149 R$ | All 48 national kit ball skins (cosmetic only) |
| **VIP Lounge** | 199 R$ | Access to VIP area of hub, exclusive emote, gold name tag |
| **Coin Pack — Handful** | 75 R$ | 500 coins |
| **Coin Pack — Bag** | 175 R$ | 1,500 coins |
| **Coin Pack — Chest** | 499 R$ | 5,000 coins |
| **"Golden Boot" Trail** | 99 R$ | Golden particle trail on every shot, permanent |
| **Goalkeeper Pack** | 199 R$ | 5 exclusive glove cosmetics + keeper dive emote |

**Free-to-play feel is essential** — coins must be earnable at a meaningful rate (100–200 per 30-min session) so free players feel respected and spend socially, not under pressure.

---

## 6. Map Builder Deliverable Priority List

In rough build order (highest impact first):

1. **Watch Party Room** — single biggest social retention feature
2. **Fan Zone ring** — 6 zones, exterior architecture only (interior details second pass)
3. **Trophy Room** — centrepiece of the hub, screenshot magnet
4. **Stadium LED scoreboard** — functional SurfaceGui above the goal
5. **Dugouts and TV gantry** — stadium realism, 1 day's work
6. **VAR Room** — behind-goal photo moment
7. **Juggling pitch** — small flat area with goal post frame, 2 hours
8. **Fan Zone interiors** — NPC placements, trophy cases, emote kiosks per zone
9. **Broadcast booth** — raised box, 2 NPC seats, microphone prop
10. **Goal net billowing** — scripted Parts, coordinate with Senior Dev

---

## 7. Marketing & Discovery

### Timing
The World Cup peak is NOW. Group stage ends July 3. Knockout rounds are the highest drama (July 4–19). The Penalty Night feature should be LIVE before the Round of 16 (July 4).

### Thumbnail & Icon
- Icon: close-up of a boot striking a ball, net behind, gold WC trophy in corner
- Thumbnail: dramatic keeper-vs-shooter standoff, stadium lights, 48 nation flags montage strip at bottom
- A/B test two thumbnails: action shot vs. trophy shot

### Discovery Hooks
- **"World Cup 2026" in the game name** — players search this directly on Roblox
- **Tag stack**: Soccer, Football, World Cup, Penalty, Sports, Multiplayer, National Teams
- Sponsor a small Roblox content creator to post a 60-second clip of the Penalty Night event
- Post a replay video to the game's social channels every time a 20+ touch juggling record is set (organic virality)

### In-Game Shareability
Every Player Card, every Walk-Off win, every 10-in-a-row juggle should have a "Screenshot" button that opens Roblox's native share screen with a pre-formatted image. One shared screenshot = 3–5 potential new players.

---

## 8. Team Responsibilities at a Glance

### Senior Roblox Dev
- Phase 1 fixes (done)
- Live score API integration + DataStore schema
- Tournament bracket + nation allegiance system
- Season pass XP/tier progression
- Penalty Night event mode server logic
- Daily/weekly quest system rewrite
- Free kick, Goalkeeper Gauntlet, Walk-Off game modes
- UI overhaul (HUD, shot power, match result screen)
- Audio reactivity (crowd lerp, commentator lines)
- Anti-cheat + DataStore batching
- Multi-place teleport architecture

### Map Builder
- Fan zone ring (6 zones, phased build)
- Trophy room centrepiece
- Watch party room
- Stadium upgrades (scoreboard, dugouts, VAR room, gantry)
- Juggling pitch
- Broadcast booth
- Goal net billowing (coordinate with dev on TweenService)
- Terrain quality pass (striped turf, stadium exterior)

### Game Designer
- Matchmaking flow — when do players queue? From hub portal or auto?
- Quest content — write all daily/weekly/milestone quest copy
- Player Card design spec — visual layout, tier requirements, badge artwork briefs
- Nation allegiance UX flow — first-join nation picker, change mechanic
- Season pass tier-by-tier reward design (40 tiers × 2 tracks)
- Trivia question bank (100+ questions, rotate 5/day)
- Penalty Night rules doc — how does the parallel duel work exactly?
- Economy balancing — coin earn vs. spend rates, price of all shop items
- Tutorial flow — how does a brand new player learn the game in under 90 seconds?
- Sound brief — write exact voice lines for 8 commentator clips

---

## 9. 5-Week Sprint Timeline

```
Week 1  (Jun 13–20)   Foundation + Nation System + Tournament Bracket
Week 2  (Jun 21–27)   Minigames (Free Kick, GK Gauntlet, Trivia, Walk-Off) + Watch Party Room
Week 3  (Jun 28–Jul 4) Hub Expansion (Fan Zones v1, Trophy Room) + Season Pass launch
                        ↑ Round of 32 begins Jul 28 — Penalty Night must be live
Week 4  (Jul 5–11)    Season Pass content, Stadium polish, Audio pass, UI overhaul
Week 5  (Jul 12–18)   Player Cards + Sticker Album, final polish, anti-cheat sweep
Jul 19                 WORLD CUP FINAL — Penalty Night Grand Finale event
                        "I Was There" badge goes live. Season Pass closes.
```

---

## 10. Success Metrics

| Metric | Target by July 19 |
|--------|------------------|
| Total visits | 500,000+ |
| Peak concurrent players | 500+ |
| Day 1 retention | 35%+ |
| Day 7 retention | 15%+ |
| Premium Season Pass conversion | 4–6% of players |
| Average session length | 25+ minutes |
| Nation leaderboard entries (active nations) | All 48 represented |
| Penalty Night peak concurrent | 200+ per event |

---

*"We don't need to be the biggest football game on Roblox. We need to be the one people remember."*

---

### Sources consulted
- [FIFA World Cup 2026 Schedule — FIFA.com](https://www.fifa.com/en/tournaments/mens/worldcup/canadamexicousa2026/articles/match-schedule-fixtures-results-teams-stadiums)
- [FIFA × Gamefam Roblox Event launch — GamesBeat](https://gamesbeat.com/gamefam-launch-fifa-world-cup-2026-super-soccer-roblox/)
- [FIFA World Cup 2026 Roblox Event — Digital Reviews Network](https://www.digitalreviews.net/news/pressers/fifa-world-cup-2026-roblox-event/)
- [Roblox Retention Benchmarks 2026 — BLOXG](https://bloxg.com/statistics/roblox-retention-benchmarks)
- [Roblox Player Retention Strategies — BLOXG](https://bloxg.com/guides/roblox-player-retention)
- [World Cup 2026 Schedule & Format — Good Morning America](https://www.goodmorningamerica.com/culture/story/fifa-world-cup-2026-schedule-group-stage-133715983)
- [Top Roblox Games Analysis 2026 — StudioKrew](https://studiokrew.com/blog/top-games-on-roblox-and-analysis-2026/)
