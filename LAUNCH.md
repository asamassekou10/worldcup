# Penalty Kings — Launch & Discovery Kit (Phase 5)

The in-game systems are built. These are the **top-of-funnel** levers that actually
drive a viral spike during the World Cup window. Icon/thumbnail **art** and posting
**clips** are the two things only you can do — everything else below is ready.

---

## 1. Store listing copy

**Title (≤ 50 chars, put the hot keyword first):**
> ⚽ Penalty Kings: World Cup Shootout

Alternatives to A/B test:
- `⚽ World Cup Penalty Kings ��`
- `Penalty Kings ⚽ Shootout (World Cup)`

**Description:**
> ⚽ **PENALTY KINGS — the World Cup penalty shootout!** ⚽
>
> Pick your country, step up to the spot, and bend it into the top corner. Read the
> keeper, curve the ball around the dive, and bury the winner in front of a packed
> stadium.
>
> 🌍 **Rep your nation** — every goal you score climbs your country up the global
> World Cup Standings.
> 👟 **Golden Boot** — chase the weekly top-scorer crown (resets every Monday).
> 🎯 **Daily quests + login streaks** — come back daily for coins and XP.
> 🧤 **Real keeper duels** — outguess a diving keeper in fast free-for-all matches.
> ⭐ **Level up & unlock** nations and flex your kit.
>
> Up to 8 players. Mobile-friendly. Made for the 2026 World Cup hype. Who's the
> Penalty King? 👑

**Tags / "Genre":** Sports / Competitive. **Max players:** 8.

---

## 2. Icon (512×512) — the single biggest CTR lever

- Tight crop: a **ball rocketing into the top corner** + a **diving keeper** silhouette,
  motion blur on the ball.
- One **bold flag** (rotate the most-played nation) + a gold **👑** accent.
- Huge contrast, readable at thumbnail size. Minimal text (maybe just "⚽👑").
- Test 2–3 icons; Roblox rewards CTR. Swap the flag to match trending nations.

## 3. Thumbnails (1920×1080) — shot list

1. **Hero:** broadcast angle — ball mid-curve, keeper full-stretch dive, packed crowd
   + floodlights behind. Caption: "BEND IT IN 🌀".
2. **Nation pride:** the lobby nation picker / flags + "REP YOUR COUNTRY 🌍".
3. **Golden Boot:** the standings board + "CHASE THE GOLDEN BOOT 👟".
4. **Goal celebration:** fireworks + trophy lift + "SCORE THE WINNER 🎉".
5. **Social:** 8 avatars on the pitch + "PLAY WITH FRIENDS" (after Phase 3).

## 4. Clips to post (TikTok / YT Shorts / Reels) — the real discovery engine

- Last-second **curve winner** into the top bins (slow-mo goal-cam).
- **Keeper save** montage with the camera shake.
- "Rate my panenka" / fails — comment bait.
- Nation-pride angle: "Scoring for every country" series.
Pin the game link; post daily during matchdays.

---

## 5. Badges to create (Creator Dashboard → Badges)

Create each, paste its id into `Config.Badges` (currently `0` = not awarded yet).
Already wired in `BadgeService` + `DataService`:

| Config key  | Badge name        | Awarded when                    |
|-------------|-------------------|---------------------------------|
| `FirstGoal` | First Goal        | score your first goal           |
| `FirstWin`  | Champion          | win your first match            |
| `HatTrick`  | Hat-Trick Hero    | 3+ goals in one match           |
| `Level5`    | Rising Star       | reach level 5                   |
| `Level10`   | Veteran           | reach level 10                  |
| `Streak3`   | Loyal Fan         | 3-day login streak              |

Badges show on player profiles → social proof + completion pull.

---

## 6. Pre-publish checklist

- [ ] Paste real ids into `Config.Monetization` (gamepass + coin packs) and
      `Config.Badges`.
- [ ] In Game Settings, enable **Studio API access to DataStores** is for testing;
      the live game just needs the place **published** (OrderedDataStore boards +
      ProfileStore go live automatically).
- [ ] Set icon + 5 thumbnails + description above.
- [ ] Confirm the stadium markers (`Ball`, `Keeper`) are placed + anchored
      (see `STUDIO_SETUP.md`).
- [ ] Publish, then smoke-test on a live server (boards/badges only work live).
