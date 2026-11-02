# Art sources

Everything under `res/` except generated content comes from Marc Risney's
WildCurrent project (`github.com/mrisney/WildCurrent`, `assets/art/`):

| Here | WildCurrent source |
|---|---|
| `props/tree-canopy-*` (incl. `-vine-`), `bush-clump-*`, `landmark-boulder-*`, `vine-mat-*`, `waterline-*` | `bank/` |
| `props/floating-log.png` | `hazards/floating-log-river-01.png` |
| `effects/surf-sheet.png` | `effects/fort-point-swell/fort-point-swell-sheet.png` (3×2 frames, 256×192) |
| `boats/dinghy-HHH.png` | `sailing/runtime/competitive_dinghies/upwind-white/heading-HHH.png` (12 headings, clockwise from up) |
| `structures/dock.png` | `structures/dock-small-01.png` (shore end at the top) |

The sprites are top-down. In 3D they're laid on shallow domes or flat cards
(see `render/SpriteProps.hx`, `render/Surf.hx`, `render/Boats.hx`).
