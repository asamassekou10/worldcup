# Hooking the game up to your stadium

The game plays on **your hand-built stadium in the Workspace**. It finds the pitch
from **four marker parts** you name; everything (aim, ball/keeper, camera, the
crowd/decor that fills the field, the Free Kicks far goal) is derived from them —
so your stadium can sit anywhere, at any rotation, any size.

If you **move or rotate the whole pitch, the markers must move with it.** The
easiest way: **put the four markers INSIDE your pitch model** (drag them under
`Football Pitch` in the Explorer). Then they rotate/translate together and you
never touch coordinates again.

## The four markers (name them EXACTLY these)

| Name      | Where to place it                                   |
|-----------|-----------------------------------------------------|
| `Ball`    | the **penalty spot** in front of the near goal      |
| `Keeper`  | the **center of the near goal line**                |
| `Center`  | the **halfway line** (center circle)                |
| `FarGoal` | the **center of the far goal line** (opposite goal) |

Rules:
- Each must be a **single anchored Part** (or a Model — it uses the model's
  position). Set `Transparency = 1` if you don't want them visible.
- Only **one** part may carry each name (rename/remove any duplicates).
- Position is all that matters — orientation/size of the markers is ignored.
- `Ball` doubles as the match ball (it animates during a shot), so make it the
  real soccer ball on the spot. If you see **"Cage Mesh Id for Ball is empty"** in
  the Output, your `Ball` is a MeshPart with no mesh — swap it for a clean ball
  mesh or a plain `Part` (the warning is harmless, but a clean part avoids it).

## What each marker drives
- **Ball + Keeper** → the goal, the aim, the penalty camera, where players stand.
- **Center** → the field length/width: the lobby/hub move to midfield, the crowd
  fills the whole pitch, the prediction/photo/stall props spread out.
- **FarGoal** → the **Free Kicks practice** runs at your real far goal.

## Your current situation (from the screenshot)
- The stadium content is under `[PUT IN WORKSPACE]` (the toolbox author's note).
  It's fine nested under `Football Pitch` — the game searches recursively — **as
  long as the four markers are positioned correctly on the pitch**.
- You **moved/rotated the pitch** (Position -59, 4, -53; Orientation 0, 90, 0), so
  the old `FarGoal` coordinate I had is stale. Re-place the markers on the pitch as
  it sits now (or parent them inside `Football Pitch` so they're always correct).

## Then
1. **Connect Rojo** (plugin panel → port `34873` → Connect) so the latest code is
   in the place.
2. Press **Play** with **2 players** (Test → Clients & Servers → 2), hit **FIND
   MATCH** in both → a shootout runs on your pitch.
3. If your goal opening isn't ~**21 wide × 8 tall** studs, tell me the real size
   and I'll set `Config.Goal` so the aim lines up.
