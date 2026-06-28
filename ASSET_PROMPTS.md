# Asset Prompts — ready to paste into your image generator

Copy/paste prompts for the Tier-1 (discovery) and Tier-2 (core UI) assets from `ASSET_PLAN.md`.
Works with Midjourney / DALL·E / Ideogram / Leonardo etc. Generate, then upload to Roblox
(Asset Manager → Images) and send me the IDs and I'll wire them in.

> **Reuse this STYLE LINE on every UI icon** so the set is cohesive:
> `bold semi-flat vector icon, thick clean outlines, 2–3 flat colors plus one soft highlight, vibrant,
> centered on a transparent background, ~8% padding, reads clearly at 32px, no text, soccer/World Cup
> theme, palette pitch-green #3CC85A + trophy-gold #FFD24B + deep-navy #141826`

---

## 1. GAME ICON — 512×512 (most important)

```
Mobile game app icon, 512x512, square. A heroic cartoon soccer goalkeeper in a vivid jersey diving
sideways to save a glowing golden soccer ball, dramatic stadium floodlights and bokeh behind, confetti.
Bold 3D-rendered "Roblox front page" style, glossy lighting, thick rim light, extremely high contrast,
saturated colors, dynamic low angle. Centered subject, no text, no logos. Trophy-gold and pitch-green
palette. Eye-catching even as a tiny thumbnail.
```
Alt concept: swap the keeper for a giant gold **World Cup trophy** erupting with confetti and coins.

---

## 2. THUMBNAILS — 1920×1080 each (the game-page carousel)

Big readable text is allowed here. Render style = glossy 3D, dramatic, "front page".

**T1 — The shootout (hero):**
```
1920x1080 game thumbnail, glossy 3D cartoon style. A Roblox-style soccer player blasting a flaming ball
past a diving goalkeeper in a packed neon stadium, motion blur, confetti, dramatic lighting. Big bold
3D text top-left: "PENALTY KINGS". Vibrant, high contrast, World Cup colors. Leave the right third clear.
```

**T2 — Would You Rather (your viral hook):**
```
1920x1080 game thumbnail, glossy 3D cartoon style. Two giant glowing doorways on a neon runway, one blue
one orange, a Roblox character running toward them, big "% choose" vote bars floating above. Huge bold
text: "WOULD YOU RATHER?". Energetic, colorful, mysterious lighting.
```

**T3 — Prizes / progression:**
```
1920x1080 game thumbnail. An explosion of gold coins, collectible cards fanning out, and a glowing
trophy, a happy Roblox character holding a giant coin. Bold text: "EARN COINS · COLLECT CARDS". Bright,
celebratory, confetti, treasure vibe.
```

**T4 — Predict the World Cup:**
```
1920x1080 game thumbnail. A glowing crystal ball showing two national-flag soccer teams facing off, a
character pointing confidently, percentage bars and a streak fire icon. Bold text: "PREDICT THE WORLD CUP".
Dramatic purple-and-gold lighting.
```

**T5 — Tournament / compete:**
```
1920x1080 game thumbnail. A golden trophy on a podium with a leaderboard and a tournament bracket glowing
behind, three Roblox characters celebrating 1st/2nd/3rd. Bold text: "WEEKLY TOURNAMENT · WIN PRIZES".
Stadium lights, confetti, premium gold look.
```

---

## 3. CURRENCY & PACK ICONS — 256×256, transparent PNG

**Coin** (the most-used icon in the game):
```
[STYLE LINE] — subject: a single shiny gold coin seen at a slight 3/4 angle, a small soccer-ball emboss
on its face, glossy highlight and thin dark outline.
```

**XP / Level:**
```
[STYLE LINE] — subject: a bright blue upward chevron star badge (level-up emblem), glowing.
```

**Card pack:**
```
[STYLE LINE] — subject: a sealed foil trading-card pack, soccer themed, a few card corners peeking out
the top, gold + green wrapper with a star.
```

---

## 4. THE MENU ICON SET — 256×256, transparent PNG (one cohesive set of 11)

Prefix EACH with the **STYLE LINE** above, then the subject. (Note: today Shop & Daily Deals both use
🛒 and Ranks & Tournament both use 🏆 — these give each a *distinct* icon.)

| # | Item | Subject to append to the STYLE LINE |
|---|------|--------------------------------------|
| 1 | **Play Modes** | a green glossy play ▶ button inside a soccer ball |
| 2 | **Shop** (nations) | a folded soccer jersey with a small generic flag, on a hanger |
| 3 | **Ranks** (leaderboard) | a 1-2-3 winners' podium with a gold star above first place |
| 4 | **Store** (premium) | a faceted cyan/purple gem with a sparkle |
| 5 | **1V1** | two crossed soccer cleats… no — two crossed silver swords with a tiny soccer ball at the cross |
| 6 | **Club** (idle earner) | a small stadium/arena building with a gold coin above it |
| 7 | **Cards** | three collectible cards fanned out, soccer themed |
| 8 | **Daily Deals** | a red price/sale tag with a gold coin and a small clock |
| 9 | **Tournament** | a gold trophy with a glowing bracket behind it |
| 10 | **Trade** | two curved arrows forming a circle (swap) with a small card on each side |
| 11 | **Predict** | a purple crystal ball with a soccer ball inside, glowing |

> Generate all 11 in **one session with the same seed/style** so the set matches. Send me the 11 IDs
> (+ coin, XP, pack) and I'll replace the emoji with `ImageLabel`s across the MENU and panels.

---

## Hand-off checklist

- Game icon → Roblox **game settings** (you upload this one directly).
- Thumbnails → game page (you upload these directly).
- Coin / XP / pack / 11 MENU icons → Asset Manager → Images → **paste the IDs here or to me**.
- Gamepass / coin-pack icons → see `STORE_IMAGES.md`.
- Badge icons → see `BADGES.md`.
