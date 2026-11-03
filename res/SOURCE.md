# Art sources

Everything under `res/` except generated content comes from Marc Risney's
WildCurrent project (`github.com/mrisney/WildCurrent`, `assets/art/`):

| Here | WildCurrent source |
|---|---|
| `props/tree-canopy-*` (incl. `-vine-`), `bush-clump-*`, `waterline-*` | `bank/` |
| `props/floating-log.png` | `hazards/floating-log-river-01.png` |
| `structures/dock.png` | `structures/dock-small-01.png` (shore end at the top) |

The sprites are top-down. In 3D they're laid on shallow domes or flat cards
(see `render/SpriteProps.hx`). The boulder and vine-mat sprites were
removed: rocks are 3D now (`render/Rocks.hx`), and the mats were unused.
