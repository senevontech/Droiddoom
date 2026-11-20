# Sound effects: real recordings vs. the synthesized fallback

The game plays every sound **by name**. For each name it uses, best first:

1. **Real recordings** in `game/assets/audio/sfx_real/`:
   `<name>.ogg` or `<name>.wav`, plus optional extra takes
   `<name>_2`, `<name>_3` … `<name>_6`. One take is picked at random each
   time it plays, which makes gunfire sound much less repetitive.
2. **Synthesized fallback** in `game/assets/audio/sfx/`, made by
   `py -3 tools/gen_sfx.py` (original, licence-free, always present).

Dropping a file in `sfx_real/` is all it takes. No code changes are needed.

## The names

| Name | What it should be |
|---|---|
| `shot_rifle` | Assault-rifle / carbine single shot, outdoors (short tail) |
| `shot_scatter` | Shotgun blast (optionally with the pump rack at the end) |
| `shot_laser` | Short electric buzz/zap, very short (it repeats 20×/s while firing) |
| `shot_rail` | Very loud, sharp crack with a metallic ring (anti-materiel rifle + electric layer works) |
| `shot_rocket` | Rocket / RPG launch whoosh |
| `shot_grenade` | Grenade launcher "thoonk" |
| `shot_bolt` | Enemy energy weapon (sci-fi blaster) |
| `droid_death` | Metal crash + sparks + electric power-down |
| `explosion` | Medium explosion, outdoors, with debris |
| `impact_metal` | Bullet hitting metal armour (ping/clang) |
| `impact_world` | Bullet hitting concrete / dirt |
| `dash` | Fast mechanical whoosh / servo burst |
| `neural_sync` | Slow-motion "whoom" (bass drop / time-slow effect) |
| `hollow_hit` | Heavy metal plate being hit (player taking damage) |
| `wave_start` | Alarm / alert chime |
| `reload` | Magazine out + in + charging handle |

**Prepare files like this:** mono is fine (3D sound is mono anyway). Trim the silence at the start: sounds must begin instantly. Keep shots under about 1.5 s and explosions under about 3 s. OGG is smaller than WAV.

## Where to get recordings (free, licence-checked)

The project rule is **free / CC0 assets only** (D-017). Before using a file, open its page and read the licence there, then log it in `docs/ASSET_LICENSES.md`: name, source URL, author, licence and date.

- OpenGameArt: *The Free Firearm Sound Library* (stated CC0), *Combat Sound Effects Pack* (CC0 compilation; check its LICENSES.txt), *Residue SFX* (CC0). Real gunfire, reloads and explosions.
- Kenney.nl: *Impact Sounds* and *Sci-fi Sounds* (CC0). Good for `impact_*`, `shot_bolt`, `shot_laser`, `neural_sync` and `wave_start`.
- Sonniss GameAudioGDC bundles: royalty-free for games but **not CC0** (custom licence, tens of GB). Only use them after the licence is approved and logged.

Sites differ on whether they need attribution. CC0 doesn't, but crediting the authors in the game's credits is still a nice touch.
