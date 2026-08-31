# K A L K I I : Genesis — project guide

Paper Mario-style 2.5D story-based action shooter (punch/kick + guns).
Target: **Steam + Android**, ~2hr gameplay, "cool" cyberpunk aesthetic.
User = creative director, assistant = lead engineer.

## Engine
- Godot **4.6** (exe: `C:/Games/GODOT/Godot_v4.6.3-stable_win64.exe`)
- Mobile renderer, Jolt physics, d3d12.
- Headless validate after edits:
  - `Godot ... --headless --path . --import`
  - `Godot ... --headless --path . --quit-after 5` (catches parse/runtime errors)

## Architecture — "Paper Mario" done right
Flat 2D sprites as **upright Y-billboards** (`Sprite3D`/`AnimatedSprite3D`, `billboard=2`,
`alpha_cut=1`, `texture_filter=3`, `pixel_size=0.0025`) inside a **real 3D world**, so depth
and occlusion are handled by the engine — unlike the abandoned Three.js prototype.

## Current state
- `scenes/main.tscn` + `scripts/main.gd`: world built in code (floor, sun, env, box props, follow camera at rot -32°, pos (0,7,10)).
- `scenes/player.tscn` + `scripts/player.gd`: `CharacterBody3D`, WASD + arrows, SPEED 6, GRAVITY 20.
- `scenes/player_frames.tres`: SpriteFrames — `walk` (3 frames, speed 8), `front`, `back`.
- Walk art is **side profile only**: side-walk on horizontal move; static front/back on vertical move/idle.

## Sprites
- Source art lives in `C:/Users/xczma/Desktop/char/naoh/` on a **magenta background** (~239,14,229).
- Clean via chroma-key + despill (see assistant memory `magenta-sprite-keying`): score `s=min(R,B)-G`,
  alpha ramp 35..110, despill `R-=over; B-=over`. Multi-pose sheets split on widest magenta column gap.
  Detect figures as largest connected row-run (drops labels). Normalize height ~1100, foot-align.
- Output to `assets/sprites/player/...`.

## Pre-ship TODO
- Gemini API key sits in plaintext in `project.godot` — move out before any repo/build push.
- `ziva_agent` / `ziva_installer` addons are broken (missing native DLLs) — disable to stop console spam.

## Next up
Combat: punch/kick + shoot with hitboxes and a reacting enemy. Then enemy AI, level art, Steam/Android export.
