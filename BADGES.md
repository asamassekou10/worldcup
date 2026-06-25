# Penalty Kings — Badges

All 9 badges are already wired in code (`BadgeService` + `Config.Badges`), sitting dormant at
`id = 0`. To turn them on:

1. **Create each badge** on the dashboard (below) → Roblox gives you a **Badge ID**.
2. **Send me the IDs** → I drop each into `Config.Badges` (one line each) and they go live.

## How to create a badge (Creator Dashboard)
**Creations → Penalty Kings → Engagement → Badges → Create a Badge** →
upload the **512×512 icon**, paste the **name** + **description**, Create.
> Badges cost **100 Robux each** to create. Make the high-value ones first if budget matters
> (suggested order: First Goal → Winner → Decision Maker → Hat-Trick → the rest).

## Shared icon style (paste at the end of each prompt)
> Roblox-style 3D rendered circular achievement medallion, glossy gold rim, a single bold
> centered icon, vibrant saturated colors, soft studio lighting, simple radial gradient
> background, clean, reads clearly at small size, no text --ar 1:1 --style raw

---

## The 9 badges

| Config key | Badge name | Description (paste into Roblox) |
|---|---|---|
| `FirstGoal` | **First Goal! ⚽** | Score your very first penalty. Welcome to the World Cup! |
| `FirstWin` | **Champion 🏆** | Win your first penalty shootout. |
| `HatTrick` | **Hat-Trick Hero 🎩** | Score 3+ goals in a single match. |
| `Level5` | **Rising Star ⭐** | Reach Level 5. |
| `Level10` | **Pro Striker 🌟** | Reach Level 10. |
| `Streak3` | **Loyal Fan 🔥** | Play 3 days in a row. |
| `ChoicesFirstRun` | **Decision Maker 🤔** | Finish your first "Would You Rather" run. |
| `ChoicesCollector` | **Legend Collector 🏅** | Collect 10 legends in the Choices runner. |
| `ChoicesAllLegends` | **Hall of Fame 👑** | Collect every legend. The ultimate flex. |

## Icon prompts

**First Goal! ⚽** — a glowing soccer ball rocketing into the top corner of a net, motion lines,
green-and-gold glow, [shared style]

**Champion 🏆** — a shining golden World Cup–style trophy with sparkles and confetti, triumphant
gold glow, [shared style]

**Hat-Trick Hero 🎩** — three glowing soccer balls in a row with a sleek black top hat above them,
playful, gold-and-purple glow, [shared style]

**Rising Star ⭐** — a single bright gold star with an upward swoosh and small sparkles, energetic
blue-and-gold glow, [shared style]

**Pro Striker 🌟** — a glowing soccer cleat striking a star-burst, dynamic, electric blue-and-gold
glow, [shared style]

**Loyal Fan 🔥** — a blazing flame forming a "3" (or a flame over a calendar), warm orange-red glow,
[shared style]

**Decision Maker 🤔** — two glowing doorways (one blue, one orange) with a thinking-face spark
between them, clever purple glow, [shared style]

**Legend Collector 🏅** — a stack of glowing collectible legend cards fanned out with a medal on
top, prestige gold glow, [shared style]

**Hall of Fame 👑** — a radiant golden crown above a row of tiny glowing legend silhouettes,
majestic gold-and-purple glow, [shared style]

---

## After you create them
Paste the IDs here (or just message them) and I'll wire them in, e.g.:

```lua
Badges = {
    FirstGoal = 1234567890,   -- <- your real IDs
    FirstWin  = 1234567891,
    ...
}
```

Until then they stay dormant (`BadgeService.tryAward` skips `id = 0`), so nothing breaks.

## Want more badges?
These 9 cover the core loop. Easy adds if you want them (each needs a tiny code hook + a new
`Config.Badges` entry — tell me and I'll add the hook):
- **Daily Devotee** — 7-day play streak
- **World Cup Winner** — finish your nation's run / score in a featured match
- **Speed Demon** — finish a Choices run under the target time
- **The Rebel / The Loyalist** — earn a personality-card title
