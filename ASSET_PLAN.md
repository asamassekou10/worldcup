# Asset Plan — images & icons to level up Penalty Kings

What to make, where it's used, the exact size, and the priority. The game currently runs on **emoji
placeholders** for almost every icon (💰 coins, the MENU tiles, 🃏 cards). Swapping the high-traffic
ones for real art is the single biggest "looks like a real game" upgrade.

See also: **STORE_IMAGES.md** (gamepass/product icon prompts — already written) and **BADGES.md**.

---

## 0. Art direction (read first — keeps everything cohesive)

Pick ONE style and use it for every asset so the game reads as a single product:

- **Bold, semi-flat, vibrant.** Thick clean outlines, 2–3 flats + a highlight. Reads at 32px.
- **Palette:** pitch green `#3CC85A`, trophy gold `#FFD24B`, deep navy UI `#141826`, with team accent
  colors. (These already match the in-game UI.)
- **Store/thumbnail art** is the exception — go big, glossy, 3D-ish render style (the "Roblox front
  page" look): expressive characters, dramatic lighting, huge readable text.
- Export **PNG with transparency** for every UI icon; square canvas, subject centered with ~8% padding.

---

## 1. Discovery & monetization — DO FIRST (biggest impact on installs + revenue)

| Asset | Size | Where | Notes |
|---|---|---|---|
| **Game icon** ⭐ | 512×512 PNG | The thumbnail players see in search/sort. THE most important image. | One hero: a keeper diving + a glowing ball, or the trophy. Bold, minimal text, high contrast. |
| **Thumbnails ×5–10** ⭐ | 1920×1080 | The carousel on the game page. Drives click-through. | 1: the shootout. 2: **Would You Rather** doors (your viral hook). 3: prizes/coins/cards. 4: "PREDICT THE WORLD CUP". 5: trophy/tournament. Big text, action shots. |
| **Gamepass icons** | 512×512 | Store panel (2× Coins Forever, etc.) | Prompts already in `STORE_IMAGES.md`. |
| **Coin-pack product icons** | 512×512 | Store (Handful/Bag/Chest of Coins) | Prompts already in `STORE_IMAGES.md` (chest/bag/handful). |

> These four lines are ~80% of the commercial value. If you do nothing else, do these.

---

## 2. Core UI icons — the premium-feel upgrade (replace emoji)

All **256×256 PNG, transparent**, used as `ImageLabel`s. I'd wire these in once you provide them.

| Asset | Replaces | Used where (high traffic!) |
|---|---|---|
| **Coin** ⭐ | 💰 | HUD balance, Daily Deals prices, Tournament prizes, prediction reward, field coins. Everywhere. |
| **XP / level badge** | ⭐ emoji | Top-left level chip + XP bar |
| **Card pack** | 🃏 | Cards button, "open pack", reveal |
| **The 10 MENU tile icons** | 🎮🛒🏆💎⚔️🏟️🃏🛒🏆🔄🔮 | The unified MENU grid. A matching set of 10 flat icons = instant polish: Modes, Shop, Ranks, Store, 1V1, Club, Cards, Daily Deals, Tournament, Trade, Predict. |

> The **coin** is the highest-ROI single icon in the whole game — it appears in nearly every panel.
> A consistent **MENU icon set** is the most visible "designed, not thrown together" signal.

---

## 3. In-world / 3D & textures (atmosphere)

| Asset | Type | Where | Notes |
|---|---|---|---|
| **Coin model** | mesh (or keep current `2683656699`) | field + WYR pickups | Current toolbox model works; a custom low-poly gold coin would match better. |
| **Mascot model** | rigged R15 character | WYR "become a legend" morph | The current toolbox "chalk bot" doesn't animate cleanly. A proper rigged mascot (or a Roblox bundle) would fix the legs/facing for good. |
| **Stadium ad-boards** | 512×128 textures | perimeter LED boards | "PENALTY KINGS", sponsor-style banners, World Cup 2026 — sell the stadium feel. |
| **WYR door art** | 1024×1024 | the choice doors | Per-prompt door images (the `image` field already exists in `ChoiceBank`). Optional but very shareable. |
| **Center-circle crest** | 1024×1024 decal | midfield | Replace the text "🏆 2026" SurfaceGui with a real crest decal. |
| **Custom skybox** | 6× 1024 | sky | Currently a default Roblox sky; a dusk-stadium sky would lift every screenshot. |

---

## 4. Card collection art (makes the collectible loop compelling)

The 21 cards (`CardBank.luau`) currently show **emoji** on tiles. Custom art turns the collection from
"a list" into "gotta catch 'em all."

- **21 card faces**, ~512×512 (or 2:3 trading-card aspect), grouped by rarity color.
- Roles (Keeper/Defender/…) = silhouette art; Nations = crest/flag art; Legends = gold premium frames.
- **Tip:** this is 21 images — do it as a batch with one template/prompt so they're consistent. Lower
  priority than §1–2, but a strong retention play once the basics are done.

---

## 5. Badges (almost done)

`BADGES.md` has the spec. **150×150 PNG.** 5 are live; 4 still need art + IDs:
**Streak3, ChoicesFirstRun, ChoicesCollector, ChoicesAllLegends.** Quick win.

---

## Suggested order

1. **Game icon + 5 thumbnails** (installs).
2. **Coin icon + the 10 MENU icons** (premium UI feel) — I'll wire them in.
3. **Gamepass + coin-pack icons** (revenue; prompts ready in STORE_IMAGES.md).
4. **4 badge icons** (quick).
5. **Card art batch** + in-world textures (depth, once the above ship).

When you hand me any of the UI icons (§2), I swap the emoji for `ImageLabel`s — it's a fast change and
the game immediately looks a tier higher.
