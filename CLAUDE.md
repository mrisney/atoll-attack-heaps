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
node scripts/snapshot.mjs --dist=30 "--fly=0.24,0.62;0.42,0.13"   # fly via minimap, shot per spot
haxe build-hl.hxml && hl bin/game.hl     # desktop HashLink (x86 only)
./scripts/build-mac-native.sh            # HashLink/C native build (Apple Silicon)
```

URL params on the web build make runs reproducible:
`bin/index.html?seed=123&style=painted|sketch|inkmap&shape=atoll|single&dist=80&at=-38,0`
(`at` aims the camera at a world point; more reliable than `--fly` for close-ups).

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

- Three visual styles, cycled with **T** (Painted → Ink map → Sketch).
  **Painted is the default**: the owner judged it "the best looking one,
  most natural" once it had the FFT ocean, froth, palms and 3D rocks. Sketch
  was the default briefly before that.
  - **Classic** (the Flutter game's posterised bands and stepped water) was
    **retired at the owner's request**: "the depth bands are too unnatural".
    `?style=classic` now opens Painted. Don't reintroduce hard bands.
  - **Painted** blends painted grass/dirt/rock/sand textures
    (`GroundTextures`, generated in code, no external assets), uses soft
    turquoise water, and turns tilt-shift on (**B** toggles it). It's the
    "richer ground" direction: stylized and hand-painted, **not**
    photoreal. The owner looked at Defilade's photo-scanned terrain and chose
    this instead, because it fits the art direction and must run on phones.
  - **Ink map** uses soft colours, topo contours, coastline, slope hatching,
    and a screen-space ink pass.
  - **Sketch** comes from architectural presentation drawings the owner
    shared (paper, one warm timber material, drafting lines). The owner then
    asked for **no topographic lines** (no contours or slope hatching).
    Relief comes from real sun shading (`TerrainStyle.light`), and colour is
    **muted earth tones, not bright green/blue**. `SketchTone` remaps each
    island material's brightness and keeps a fraction of its hue (`chroma`),
    biased warm (`Palette.SKETCH_EARTH`). The ground gets a lighter curve,
    props a darker one. The ground uses the painted textures for detail.
    **No inked coastline** either (owner: remove "the black lines that trace
    the outline of the coastline"); the shore reads from the water and a
    slight froth (`breakers` 0.6).
    **The water is not toned and has no line work**: the owner preferred
    it "like the others, but darker" (`WaterShader.setSketchColors`, a dark,
    muted slate-teal, with the same waves and froth). Anything added *after* it's applied in
    `IslandView`'s constructor (docks, the flag pole) keeps its colour. That
    warm timber is the point of the style, so new built things (ships,
    forts) should be timber and stay un-toned. `ui/DraftingOverlay` is the
    UI layer: title block, scale bar, north arrow, apex datum, landing
    labels, and move orders as dimension lines. The page fade lives in
    `InkEdge` (`paperFade`), so it needs the ink pass on.
- Two island shapes, toggled with **G**: **Single** (port of the Flutter
  generator, same defaults) and **Atoll** (reef ring).
  Both get `Island.roughenCoast()` afterwards: warped noise added only near
  sea level, so coasts have coves, points, tide pools and skerries (the
  owner found the smooth coastline "a little too simple"). It changes the
  sim heightfield, so it must stay deterministic.
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
- **Sprite trees are the default** in Painted and Sketch (P toggles low-poly).
  The owner found the low-poly trees "blocky, artificial". The sprites come
  from his WildCurrent repo (`assets/art/bank`). `SpriteProps` puts each on an
  alpha-tested smooth dome, trims the art's 1 px pale outline, and bleeds edge
  colour so mipmaps don't halo. Ink map keeps low-poly by default.
- **WildCurrent art in use** (see `res/SOURCE.md`): canopies (plain and
  vine), bushes, vine mats, waterline/tall grass, reeds, the floating
  log and the dock (landing beaches). The swell-sheet surf sprites
  (crescent "arches") were **removed at the owner's request**: breaking waves
  are now froth from the wave simulation (see Ocean waves). Racing
  spinnakers, rafts, buoys and city pieces were judged off-theme for the island.
  Ambient sailboats were tried and **removed at the owner's request**. Foliage sways subtly, per the WildCurrent
  art notes ("never rotate the whole canopy").
- **Rocks are 3D, not sprites** (`render/Rocks.hx`). The owner found the sprite
  boulders "very artificial": their painted-in light disagreed with our sun
  and the dome silhouette read as a sticker. Rocks are noise-deformed
  icospheres with fracture planes, sunk into the ground, with vertex AO and a
  triplanar painted texture. Use them for any new stone, never `ball()` gems.
- **Palms are procedural** (`render/Palms.hx`), not low-poly. The owner found the
  old ones "very angular and not very realistic". Each has a smooth, curved
  trunk tube with ring scars, plus arched, folded fronds that use a pinnate
  leaf texture painted in code and alpha-cut (leafy silhouettes and
  shadows). There's no palm art in WildCurrent; if the owner supplies some,
  it could replace the frond texture.
- **Boulders are sparse** (the owner asked for fewer random boulders), so keep
  the `rockCluster` rates in `Props` low.
- **Ocean waves** (`render/OceanWaves.hx`): the owner pointed at
  github.com/codeagent/webgl-ocean. That repo has **no licence**, so don't
  copy its code. We reimplemented the same technique (a Tessendorf FFT with
  a Phillips spectrum), but baked: a CPU 64² FFT at startup, 32 frames with
  dispersion quantised so the loop is exact, packed into a padded atlas
  (no mipmaps). `WaterShader` samples it at two scales for lighting only
  (no per-frame GPU FFT, no float render targets), so it stays cheap on
  phones. Wave strength, glint and whitecaps are set per style in
  `IslandView.setStyle`. Waves need depth, so the lagoon stays calm. The
  same data could later drive cosmetic ship bobbing.
  **Foam** is in the atlas alpha: the Jacobian of the choppy displacement
  (where crests fold), accumulated with decay and spread over the loop, as
  in the reference demo the owner liked. In the shallows the threshold drops
  (shoaling), so the swell breaks into froth that rolls in along the depth
  contours (`WaterShader.shoreCycle`) and then runs up the sand as swash
  (`TerrainStyle.swash`, same cycle formula, so keep the two in sync).
- All colours live in `render/Palette.hx` and the style shaders. Don't
  hard-code colours elsewhere.

## Camera and input

- `RtsCamera` fields (`targetX/Y`, `distance`, `yaw`) are the *desired* view,
  and the rendered view eases toward them. Use `lookAt()`/`zoom()` for glides,
  and `shift()`/`snap()`/`zoom(f, true)` for direct manipulation (drag, pinch,
  swipe) so the map stays glued to the pointer. After changing targets
  in bulk (new island), call `snap()`.
- Grab-pan keeps the grabbed ground point under the cursor
  (`screenToPlane` at the grabbed height), so it feels like moving a sheet
  of paper.
- `SelectionController` is a small state machine (`PointerMode`: Pending,
  BoxSelect, Pan, Gesture). Left mouse drag selects. Right/middle drag and
  one-finger touch drag pan. Touch press-and-hold then drag selects.
- On the web, a DOM `wheel` listener replaces Heaps' wheel event (it needs
  `deltaX` and `ctrlKey`). ctrl + wheel is a trackpad pinch and zooms, a
  small/fractional/horizontal delta is a trackpad swipe and pans, and a big
  integer delta is a mouse-wheel notch and zooms. The heuristic can misjudge
  unusual mice.
- The 2D layer is in device pixels. Scale UI by `uiScale` (devicePixelRatio)
  and use `getBounds()` for hit tests so Retina works.

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
- **`hxd.Key.isPressed` is per frame.** Headless software rendering runs at
  only about 4 fps with the full scene, so hold keys about 1.5 s in automation
  or the press can fall between frames.
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
- **Don't switch the water to a constant depth outside the height map.** A
  hard `inside ? -h : const` step made `fwidth(depth)` spike at the border,
  which showed as a thin bright seam across the sea. Clamp the UV instead.
- When unsure of an API, read the Heaps source rather than guessing. It's
  small and readable (`h3d/`, `h2d/`, `hxd/`, `hxsl/`).

## Conventions

- Small, focused commits with a body explaining *why*.
- Keep `README.md` architecture and controls sections in sync with changes.
- Update this file when you learn a new gotcha or the owner makes a design
  decision.
