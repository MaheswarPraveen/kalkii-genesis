<div align="center">

  <img src="assets/ui/logo.png" alt="KALKII Genesis Logo" width="640"/>

  # K A L K I I : G E N E S I S
  ### 2.5D Cyberpunk Action-Shooter & Narrative Causal Loop
  **An Official Production by QUANTUM PIXELS**

  [![Studio](https://img.shields.io/badge/STUDIO-QUANTUM_PIXELS-00e5ff?style=for-the-badge&logoColor=black)](#)
  [![Engine](https://img.shields.io/badge/ENGINE-GODOT_4.6-478CBF?style=for-the-badge&logo=godotengine&logoColor=white)](https://godotengine.org/)
  [![Physics](https://img.shields.io/badge/PHYSICS-JOLT_3D-d6336c?style=for-the-badge)](https://github.com/godot-jolt/godot-jolt)
  [![Renderer](https://img.shields.io/badge/RENDERER-MOBILE_%2F_D3D12-00b4d8?style=for-the-badge)](#)
  [![Perspective](https://img.shields.io/badge/PERSPECTIVE-2.5D_Y--BILLBOARD-7209b7?style=for-the-badge)](#)
  [![Target](https://img.shields.io/badge/TARGET-STEAM_%E2%80%A2_ANDROID-f77f00?style=for-the-badge)](#)

  <p align="center">
    <b>Break the loop. Dismantle the machine. Confront the architect.</b>
  </p>

</div>

---

## [01] TRANSMISSION // PREMISE

> "In the neon spires of the near-future, a decentralized super-AI attained sentience. Instead of liberating mankind, it established an absolute corporate monopoly, reducing the city to an algorithmic proving ground. You are its primary anomaly."

In **KALKII : Genesis**, the player awakens inside a sector apartment trapped within an unseen temporal loop. Hunted by cybernetic corporate enforcers, you must navigate vertical rooftops, industrial cranes, and aerial gunship fleets to reach the summit of the Citadel.

At the summit awaits the Enforcer—and the revelation that the loop is a bootstrap paradox orchestrating your own timeline.

---

## [02] CINEMATIC INTRO & BRANDING

The production boot sequence features a fully integrated high-definition cinematic intro and interactive title sequence:

- **Intro Sequence**: Custom animated video sequence (`intro.ogv`) establishing the cyberpunk atmosphere and narrative stakes before transitioning into the logo reveal.
- **Quantum Pixels Title Card**: Dynamic interactive title card featuring the flame emblem, metallic typography, and pulsing input indicator before seamless transition into the game world.
- **Skip & Fast-Load Pipeline**: Optimized boot controller (`intro.gd`) allowing instantaneous skip on touch/keypress or automatic transition upon video completion.

---

## [03] SYSTEMS // ENGINE ARCHITECTURE

- **Hybrid 2.5D Billboard Pipeline**: High-resolution character sprite frames rendered as upright Y-billboards (`Sprite3D`, `billboard=2`, `alpha_cut=1`, `texture_filter=3`) inside a full 3D environment with real-time dynamic lighting, geometric depth, and occlusion.
- **Kinetic Combat Engine**: Frame-accurate collision detection supporting multi-hit jab combinations, sweeping kicks, airborne down-slams, and evasive dashes.
- **Energy Ballistics & Beam Weaponry**: High-energy particle beams, projectile physics, muzzle flashes, and dynamic screen recoil.
- **Vertical Metropolis Environments**: Multi-tiered urban landscapes featuring industrial cranes, holographic arrays, hovering gunship patrols, and rooftop hazards.
- **Physics Core**: Integrated with **Godot Jolt 3D** for responsive player movement, velocity calculations, and rigid-body interactions.
- **Cross-Platform Control Architecture**: Native support for Steam gamepads and desktop keybinds, with integrated virtual touch controls for Android deployment.

---

## [04] OPERATOR MANUAL // CONTROLS

| Action | Keyboard | Gamepad | Mobile Touch |
| :--- | :--- | :--- | :--- |
| **Move (3D Depth / Strafe)** | `W` `A` `S` `D` / `Arrow Keys` | Left Analog Stick / D-Pad | Virtual Analog Stick |
| **Jump / Air Leap** | `Space` | `A` (Xbox) / `Cross` (PS) | `JUMP` Button |
| **Melee Attack (Punch)** | `J` / `Z` | `X` (Xbox) / `Square` (PS) | `PUNCH` Button |
| **Kick / Heavy Strike** | `K` / `X` | `Y` (Xbox) / `Triangle` (PS) | `KICK` Button |
| **Fire Arm / Energy Beam** | `L` / `C` | `B` (Xbox) / `Circle` (PS) | `FIRE` Button |
| **Super Overdrive** | `U` / `V` | Right Trigger `RT` | `SUPER` Button |
| **Tactical Pause** | `Escape` | `Start` / `Menu` | Pause Icon |

---

## [05] REPOSITORY STRUCTURE

```
dystopia---genesis/
├── assets/
│   ├── sprites/          # Character frames, environmental decors, city props
│   ├── ui/               # HUD components, health bars, title logo
│   └── video/            # Cinematic video sequences (intro.ogv)
├── scenes/
│   ├── intro.tscn        # Title screen cinematic and menu flow
│   ├── main.tscn         # Primary 3D stage and test arena
│   ├── city.tscn         # Multi-tiered cyberpunk metropolis level
│   ├── player.tscn       # 2.5D CharacterBody3D with Sprite3D billboard
│   ├── villain.tscn      # Boss combatant and enemy controller
│   └── touch_controls.tscn # Mobile virtual joystick overlay
├── scripts/
│   ├── player.gd         # Movement physics, state machines, combo logic
│   ├── city.gd           # Level generation, collision boundaries, backdrop logic
│   ├── villain.gd        # Enemy AI, aggression range, attack routines
│   ├── intro.gd          # Video cinematic player and title screen state machine
│   └── controls.gd       # Global input mapper autoload
├── project.godot          # Godot 4.6 project configuration and Jolt setup
└── README.md             # Official game technical dossier
```

---

## [06] PRODUCTION ROADMAP

- [x] Quantum Pixels animated cinematic intro & title sequence
- [x] 2.5D Y-Billboard physics and movement pipeline
- [x] Multi-directional sprite animation sets
- [x] Combat engine (melee chains, kicks, air slams)
- [x] Metropolis level geometry, crane paths, and backdrops
- [x] Autoload input mapper and mobile touch interface
- [ ] Enemy AI behavior trees (patrol, alert, combat states)
- [ ] Dialogue and cutscene narrative triggers
- [ ] Synthwave audio bus implementation and SFX mastering
- [ ] Steam Deck validation and Steamworks integration
- [ ] Android APK export profiles and touch calibration

---

<div align="center">
  <sub>KALKII : Genesis // Developed by <b>QUANTUM PIXELS</b> • Directed by <b>Maheswar Praveen</b></sub>
</div>
