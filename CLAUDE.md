# Atoll Attack (Heaps) — notes for agents

A Haxe/Heaps RTS: procedural islands, small squads, box-select and move. It's a
port of the Flutter/Flame game at github.com/mrisney/atoll-attack. Targets are
**Steam** (HashLink/C native), **web** (JS/WebGL), and **iOS/Android**
(the same WebGL build in a Capacitor shell, planned).

## Commands

```sh
haxe build-js.hxml                       # web build → bin/game.js (fast; use this to compile-check)
./scripts/run-web.sh                     # build + serve on http://localhost:8080
node scripts/snapshot.mjs                # build + headless screenshot → snapshots/
node scripts/snapshot.mjs --style=inkmap --shape=atoll --seed=777 --walk
haxe build-hl.hxml && hl bin/game.hl     # desktop HashLink (x86 only)
./scripts/build-mac-native.sh            # HashLink/C native build (Apple Silicon)
```

URL params on the web build make runs reproducible:
`bin/index.html?seed=123&style=classic|painted|inkmap&shape=atoll|single&dist=80`.

## How to verify a change

1. `haxe build-js.hxml` must compile cleanly.
2. Run `node scripts/snapshot.mjs` (add `--walk` if units or animation changed)
   and **look at the PNG**. It exits non-zero on page errors or if the game
   never starts.
3. Gameplay feel (camera speed, unit speed, readability) can't be judged from
   a screenshot. Say what you changed and ask the human to try it.

`npm install && npx playwright install chromium` once for the snapshot script.

## Architecture rules

- `world/` and `game/` are the **simulation**. They must not import `h3d`,
  `h2d`, `hxd` or anything in `render/`/`input/`. They must stay runnable
  headless, which matters for lockstep multiplayer and a future server.
- Input never mutates units directly. It produces `game.Command` values and
  calls `sim.queue()`. The `Sim` applies them on a fixed 30 Hz tick. Commands
  are what goes over the network.
- The sim must be deterministic: no `Math.random`/`Std.random`, no time-based
  logic in `world/` or `game/`. Noise uses Int32 hashing (`world.Noise`).
  `Std.random` is only used in `Main` to pick seeds. Floats will eventually
  need care (or fixed-point) for cross-platform lockstep.
- `render/` reads the sim and draws. `UnitView.syncFromSim` interpolates
  toward sim state each frame.
- **Death is sim state, the rag doll is cosmetic.** `Command.Kill` sets
  `unit.alive = false` and records where the hit came from. `render/Ragdoll`
  then animates the body locally. It doesn't need to be deterministic or
  networked, and the sim must never read rag doll positions.
- Platform services (storage, multiplayer, achievements) will go behind small
  interfaces with one implementation per target. Don't call Steam/Capacitor
  APIs from game code.

## Art direction (decided — keep consistent)

- Three visual styles, cycled with **T** (Classic → Painted → Ink map):
  - **Classic** (default) is the Flutter game's look. Posterised elevation
    bands (sand/lowland/upland/peak), three stepped water tones, and the fbm
    "relief" highlight. Ported from `atoll-attack/shaders/island_water.frag`.
  - **Painted** blends painted grass/dirt/rock/sand textures
    (`GroundTextures`, generated in code, no external assets), uses soft
    turquoise water, and turns tilt-shift on (**B** toggles it). It's the
    "richer ground" direction: stylized and hand-painted, **not**
    photoreal. The owner looked at Defilade's photo-scanned terrain and chose
    this instead, because it fits the art direction and must run on phones.
  - **Ink map** uses soft colours, topo contours, coastline, slope hatching,
    and a screen-space ink pass.
- Two island shapes, toggled with **G**: **Single** (port of the Flutter
  generator, same defaults) and **Atoll** (reef ring).
- **Units are simple line-art figures.** Rounded shapes, paper-white fill,
  bold ink outline, no faces or surface detail. Team is shown only by tunic
  tint and the captain's pennant. **Animation is restrained:** a gentle limb
  swing while walking, still when idle. The owner explicitly does not want
  cartoony or over-animated characters.
- **Rag dolls on death** (owner asked for them). Keep them grounded: modest
  impulse, rigid limbs (no knees or elbows), friction, and settling within a
  couple of seconds. Not slapstick.
- **Props** (`render/Props.hx`) follow the elevation bands: palms, driftwood
  and stones on beaches; broadleaf groves, bushes and grass in the lowlands;
  pine forest and outcrops in the uplands; boulders and dead snags on peaks.
  Variety comes from species, per-instance colour and size, and noise
  clustering. Autumn trees are rare (about 6%) and muted.
- **Sprite trees are the default** in Classic and Painted (P toggles low-poly).
  The owner found the low-poly trees "blocky, artificial". The sprites come
  from his WildCurrent repo (`assets/art/bank`). `SpriteProps` puts each on an
  alpha-tested smooth dome, trims the art's 1 px pale outline, and bleeds edge
  colour so mipmaps don't halo. Ink map keeps low-poly by default.
- All colours live in `render/Palette.hx` and the style shaders. Don't
  hard-code colours elsewhere.

## Heaps/Haxe gotchas we've already hit

- **Heaps base classes have common method names.** `h3d.scene.Object` already
  has `sync(ctx)` (we use `syncFromSim`), and `h2d.Object` already has
  `rotate(v)` (we use `turnCamera`). A "should be declared with override" error
  means you've hit one of these. Pick a more specific name.
- **Every opaque material must have `render.ink.GeoOut`**, or the ink geometry
  pass fails to link its shader. `FlatMeshBuilder.setupMaterial()` adds it, so
  use that for any new mesh.
- **Winding:** with `culling = Back`, front faces are counter-clockwise when
  the normal points outward. `InkShape.addTri` fixes winding automatically.
- **Inverted-hull outlines** are the same mesh pushed out along normals and
  drawn with `culling = Front` in ink colour (see `InkShape`, `FlatMeshBuilder.outline`).
- **Enum constructor names clash across imported enums.** That's why it's
  `IslandShape.Single` rather than a second `Classic`.
- **Web keyboard input:** the canvas needs `globalEvents="1"` (in
  `bin/index.html`), or keys only work after focusing the canvas.
- **`hxd.Key.isPressed` is per frame.** Under slow software rendering, quick
  taps can be missed. Hold keys about 400 ms in automation.
- **Keep fragment shaders cheap**, because mobile is a target. Bake expensive
  noise into textures once per island (see `TerrainStyle.bakeRelief`,
  `WaterShader.setIsland`). Per-pixel fbm was too slow.
- **Shadows are opt-in per mesh** via `FlatMeshBuilder.shadows(mat, cast, receive)`
  or `build(parent, lit, cast, receive)`. Heaps materials cast and receive by
  default, so `setupMaterial` turns both off. The receive shader multiplies
  the final colour, so enable it **after** adding style shaders, or
  `TerrainStyle`/`WaterShader` (which set the colour outright) erase the
  shadow. Shadow tint is `Palette.SHADOW`, and map settings are in
  `InkRenderer`. Debug tip: temporarily set `shadow.color` to red to see where
  shadows land.
- **To keep something out of the ink outlines** (grass), put it in the alpha
  pass (`blendMode = Alpha`, still opaque). The geometry buffer only reads the
  default pass.
- **Assets live in `res/`** and are embedded at compile time (`hxd.Res.initEmbed()`
  in `Main.init`). Load with `hxd.Res.load("props/x.png")`. A textured mesh
  still needs vertex colours if it uses `setupMaterial` (that adds the
  VertexColor shader): give the Polygon `colors` (white or a tint).
- `cast` and `macro` are Haxe keywords. Don't use them as variable or parameter names.
- 16-bit index buffers: `FlatMeshBuilder` splits geometry into chunks under
  65k vertices.
- HXSL has `fwidth`, `fract`, `smoothstep`, `mix`, and small helper functions
  inside `SRC`. Use `fwidth` for constant-pixel-width lines.
- **HashLink's JIT doesn't run natively on Apple Silicon.** Develop with the
  web build, and ship native through HashLink/C.
- Haxe `Int` is 32-bit: a literal like `2654435761` is a `Float`, which breaks
  integer hashing. Use small multipliers or `haxe.Int32`.
- When unsure of an API, read the Heaps source rather than guessing. It's
  small and readable (`h3d/`, `h2d/`, `hxd/`, `hxsl/`).

## Conventions

- Small, focused commits with a body explaining *why*.
- Keep `README.md` architecture and controls sections in sync with changes.
- Update this file when you learn a new gotcha or the owner makes a design
  decision.
