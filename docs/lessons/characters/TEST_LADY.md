# Test-only lady character ("Chubby magic girl")

| | |
|---|---|
| Model | `assets/test_only/magic_girl/magic_girl.glb` (`MODEL_PATH` in `test_character.gd`), made by `tools/export_test_character.py` |
| Rig | Rigify deformation bones (`DEF-*`), posed by `_pose()` |
| Status | **local testing only**: gitignored, excluded from every export preset, loaded only if the folder exists |

## Entries

### Not licensed for the game (2026-10-25)
- **Cause:** the download had no licence; its hair carries Daz 3D metadata and its shape-key actions are named
  after Unreal Engine game assets, i.e. assembled from other products and likely ripped content.
- **Rule:** never ship it, never copy it into `assets/models/`, never add it to an export preset. Builds must
  fall back to the player model. See `ASSET_LICENSES.md`, "Rejected downloads".
