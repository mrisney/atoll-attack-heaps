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
  - **Ink map** is now Painted's world (painted ground, gravel, tracks, 3D
    trees and rocks, FFT water and froth, lighter cloud shadows) **without**
    Painted's grade, vignette and tilt-shift, so it's the brighter scene,
    plus a soft screen-space ink outline (strength 0.4: full strength around
    every leaf card was scribbly). The owner asked to **remove its contour
    lines** and give it "the same treatment" as the others "to look more
    consistent": no contours, slope hatching or inked coastline any more, and
    no chart-colour water or low-poly trees by default.
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
- **Rigged characters (in progress)**: the owner shared a pencil line-art
  archer (fine lines, light hatching, realistic proportions, tunic, trousers,
  soft boots) and wants four types: archer, swordsman, piker, flag-planting
  chief. Pipeline: Blender → FBX → `render/CharacterModel` (skinned body,
  rigid props hung on joints via `JointFollower`, takes Idle/Walk/Shoot/
  Slash/Thrust/Plant) drawn by `render/CharacterInk` (paper tone, screen-space
  pencil hatching from N·L, inverted-hull graphite outline as a second pass of
  the skinned material) and the rag doll mapped onto the skeleton
  (`CharacterModel.applyRagdoll`). `tools/character/standin.py` generates the
  stand-in (and documents the asset contract). Opt-in: `?figures=rigged`;
  `?gallery=1` lines up every kind and take. The reference has a face; the
  line-art rule says faceless: **unresolved, ask the owner**.
  Gotchas: Heaps merges all skinned meshes of one armature into one geometry
  but keeps only the first one's normals (so props must be rigid, not
  skinned); Blender ≥4 writes per-vertex normals Heaps mishandles (set custom
  split normals before export); Heaps'
  `SmoothTransition` breaks on quick idle/walk switches (cut for now);
  `Skin.getObjectByName` returns a detached Joint that breaks name lookups if
  added to the scene graph.
  **Heaps version**: the owner uses the haxelib **2.1.0 release** (git tag
  `2.1`); build against that. Heaps' main branch also says 2.1.0 but differs:
  it renamed `JointData.currentRelPose`/`currentAbsPose` to
  `currentRelPos`/`currentAbsPos` (go through `CharacterModel.JointPose`,
  never the fields), and turns bone "hand.L" into "hand_L" where 2.1 keeps
  "hand.L" (look up both). On 2.1, any child object added to a `Skin`
  stops its animation reaching the mesh, so `JointFollower` is a sibling of
  the figure, never a child of the skin.
- **Rag dolls on death** (owner asked for them). Keep them grounded: modest
  impulse, rigid limbs (no knees or elbows), friction, and settling within a
  couple of seconds. Not slapstick.
- **Props** (`render/Props.hx`) follow the elevation bands: palms, driftwood
  and stones on beaches; broadleaf groves, bushes and grass in the lowlands;
  pine forest and outcrops in the uplands; boulders on the gravel summit. Dead
  snags (bare trunks) were **removed at the owner's request**.
  Variety comes from species, per-instance colour and size, and noise
  clustering. Autumn trees are rare (about 6%) and muted.
- **3D procedural trees are the default** (`render/TreeGen.hx` + `ProcTrees.hx`):
  a port of **EZ-Tree** (dgreenheck/ez-tree, **MIT**, notice in
  `THIRD_PARTY.md`), which the owner found via the Codrops "Fractals to
  Forests" write-up. It grows recursive branches with taper, gnarliness,
  twist and a growth force, plus crossed leaf cards. We use its
  oak/ash/aspen/pine presets with fewer, larger leaf cards (about 3k tris
  per tree, ~360 trees on an island). There are 4 templates per species,
  instanced with yaw, scale and tint into merged meshes. Leaf and bark
  textures are painted in code (EZ-Tree's aren't used). Leaves have rounded
  normals around the crown, inner shading, sway, alpha-cut shadows. **P**
  cycles 3D → sprite → low-poly (`?trees=proc|sprites|lowpoly`). Sprite
  mode keeps the WildCurrent canopies. Bushes, vines and reeds stay sprites
  in every mode. Phones will want a lower-detail template set.
- **Sprite trees** (P, or `?trees=sprites`).
  The owner found the low-poly trees "blocky, artificial". The sprites come
  from his WildCurrent repo (`assets/art/bank`). `SpriteProps` puts each on an
  alpha-tested smooth dome, trims the art's 1 px pale outline, and bleeds edge
  colour so mipmaps don't halo. (Ink map used low-poly by default; now every
  style starts on 3D trees.)
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
  icospheres shaped by **gl-rock's scraping** (Erkaman/gl-rock, MIT, notice in
  THIRD_PARTY.md): local planar flats around random spots, limited to a
  radius by flood fill over the mesh, which gives chipped facets between
  rounded parts. Then gentle noise, sunk into the ground, with vertex AO and
  a triplanar painted texture. Use them for any new stone, never `ball()` gems.
  **Boulders cluster around the gravel high ground** (`Props.boulderSpot`: on
  it and a band below its rim, in irregular noise clumps). There are almost
  none in the meadows. The owner expects the summit to be the main area of
  conflict, and found the boulders "too scattered".
  **Coastal outcrops** (`Props.outcropSpot`/`outcrop`): occasional groups of 2–4
  larger rocks at the waterline running into the shallows, on a raised base
  so they break the surface. The owner asked for them "sparingly" and later
  to "reduce the number of rocks on the beach" (loose beach stones cut to a
  third too), so keep the noise threshold high, and **dark** (wet, weathered: shade ~0.42 in the
  water, 0.55 on the shore).
- **Palms are procedural** (`render/Palms.hx`), not low-poly. The owner found the
  old ones "very angular and not very realistic". Each has a smooth, curved
  trunk tube with ring scars, plus arched, folded fronds that use a pinnate
  leaf texture painted in code and alpha-cut (leafy silhouettes and
  shadows). There's no palm art in WildCurrent; if the owner supplies some,
  it could replace the frond texture.
- **Grass fields** (`render/GrassField.hx`): modelled on github.com/spacejack/terra,
  which the owner liked. Terra is **CC BY-NC** (non-commercial) except a few
  MIT files, so **don't copy its code**. The owner asked for terra's settings:
  **blades 85k–100k, depth 85, antialiasing on**. So grass is a **fixed
  budget around the view centre**, not grass everywhere: `blades` (default
  **200000**: the owner later asked for "more, and denser together"; lower it
  for phones with `?blades=`) and `depth` in metres (default 85, `?depth=`).
  It's split into two layers: NEAR, 60% of the blades in a patch of radius
  `depth*0.25`, fading out over a wide band, and FAR, the rest out to
  `depth*0.6`, wider, fading in under it (no visible patch edge). The
  patches **shrink as the camera zooms in** (`GrassShader.scale`, view
  distance / 45 in `setGrassFocus`), so the budget packs densest where
  blades can be seen. The ground under fields has windswept streaks
  (`TerrainStyle`, two unrelated scales, combed along the wind) so thin
  spots still read as grass. **Windswept** (owner's reference screenshot: "windswept,
  finer, closer together"): fine blades (1.3–2.5 cm wide, 30–70 cm long, 4
  segments), all laid over downwind by a constant `sweep` plus gusts, deep
  green with yellow-green tips (lifted for a sunny day: owner found it "a bit
  dark"; sunny weather lifts it further, 1.28×), about one in five with a straw seed head,
  over a brownish-olive thatch (`FIELD_GROUND`). Each blade **wraps** on a fixed world grid to the copy nearest
  the camera's look-at (`IslandView.setGrassFocus`, every frame), so blades
  never slide when panning. The vertex shader sets blades on the ground
  from an R32F height grid (bilinear by hand, matching `Island.heightAt`)
  and scales them by a field map (R field, G clump, B dryness). Blades are
  olive, translucent-lit, bent by gusts, drawn in the alpha pass, and
  receive but don't cast shadows. `TerrainStyle` tints the ground under
  fields olive (`fieldMask`), which carries the look beyond `depth`.
  **Heaps doesn't frustum-cull meshes without a `cullingCollider`**, which
  is another reason the budget is fixed. For phones, lower `blades`.
- **Grass parts around units** (`render/Trample.hx`). The owner pointed at the
  Codrops "False Earth" WebGPU write-up (it couldn't be fetched; we built
  the standard trample-map technique, which runs in WebGL). A 512² RGBA map
  over the island is stamped on the CPU each frame by every living unit.
  RG holds the push direction (outward), and B the amount, decaying over
  ~2.8 s so trails spring back. A marks "a unit is here" (not decayed).
  `GrassShader` bends blades from the root along the push and damps the
  wind there. Clear values: R = G = 0.5, **B = 0** (an early bug cleared B
  to 0.5, which flattened every blade).
- **Canopy see-through**: `Trample.CanopyReveal` dithers away tree leaves within
  ~2.2 m of a unit (from the A channel), so figures stay visible under trees.
  The owner also asked for "slightly less tree canopy density", so there are
  fewer leaf cards and the crowns start higher.
- **Antialiasing**: `h3d.Engine.ANTIALIASING = 4` (MSAA on the screen) in
  `Main.main`. MSAA doesn't apply when the scene renders offscreen
  (tilt-shift in Painted), so `InkRenderer` runs FXAA on that frame
  (`fxaa`, `?aa=0` turns it off).
- **The island is pastoral** (owner: "more uninterrupted fields, with some
  tree lines, more campus, pastoral like"): open lowland and upland are
  fields. Trees grow in winding **tree lines** (`Props.treeLineAt`, a noise
  isoline broken into runs), small **copses** (densest forest noise only),
  and rare lone parkland trees. Grass climbs high, and rock texture only
  shows near the summit. **The high point is loose gravel** (owner pointed at
  gravel textures and an aerial photo of a gravel pile): `GroundTextures.gravel`
  is painted in code (two Voronoi stone layers, mostly greys, over a sandy
  matrix; the reference textures' licences weren't usable). `TerrainStyle`
  uses it for the summit band, with damp and dusty patches. (Slump streaks
  bent along the downhill direction were **removed**: they wrapped the hill
  in fingerprint-like rings the owner found computer-made.) Bare
  rock shows only on the steepest faces. Few 3D stones and boulders, and
  only a few scattered in the meadows. Owner: "meadows
  of grass blades, windswept, where there are not trees, with some small
  amount of rocks, rocky area at the high point".
- **Boulders are sparse** (the owner asked for fewer random boulders) and live
  near the summit; keep `boulderSpot` rates low. The gravel is a touch lighter
  (owner: "slightly lighter... but not too much").
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
- **Stronghold reference** (owner shared Stronghold screenshots: "I am trying to
  match that" for terrain and grass). Painted moved toward it:
  olive/khaki blades and field ground (`Palette.GRASS_BLADE_*`, `FIELD_GROUND`),
  drier mottled patches; **worn tracks** (`render/Tracks.hx`) from the two
  landing beaches up to the apex, plus faint scuffed patches. The owner found
  the first version "very computer generated" (four spoke-like tracks of even
  width and fill, plus a plaid from small tiling noise), so they now meander
  in long bends, vary in width and wear along their length, have noise-ragged
  edges, and the shader breaks them up with noise at odd scales on rotated
  axes (never small repeating texture scales). They're stored as wear in
  the grass mask's **alpha**: blades thin out with ragged edges, `TerrainStyle`
  paints pale dusty earth, `Props` keeps trees off and drops pebbles; low dark
  **ground cover** clumps (`Props.groundCover`); drifting **cloud shadows**
  (`render/CloudShadow`, on every island material but the water, Painted only);
  a **lower sun** (~40°, `TerrainStyle.SUN`, shared by light, terrain, grass,
  water) for long shadows; and a **colour grade + vignette** in the final
  `TiltShift` pass (`InkRenderer.grade`, Painted; still applies with B off).
- **Weather** (`render/Weather.hx`): the owner wants three patterns, "fog,
  sunny and rain/stormy". Visual only (the sim doesn't know). Each style
  starts in one: **Ink map sunny** (brighter grass, light clouds), **Painted
  rain** (owner: "add rain and make the waves a bit rougher": rougher sea,
  more whitecaps and surf, dull glint, gustier grass, heavy fast clouds,
  plus rain streaks and a darker, cooler storm grade); **Sketch has no
  weather** (the owner had it on fog briefly, then: "the architectural
  drawing scene was OK, please revert that one"). Fog (calm sea, no cloud
  shadows, drifting haze thicker toward the far side) is reachable with **C**,
  which cycles, `?weather=sunny|fog|rain`. Island side: `IslandView.setWeather`
  (after `setStyle`); screen side: `InkRenderer.setWeather` → the final
  `TiltShift` pass (rain layers, storm grade, fog). W is taken by WASD.
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
