# Importing models: lessons

For every model that comes from Blender, a download (BlenderKit, Sketchfab, CGTrader …) or a generator.

## Checklist

1. **Licence first.** Record source, author and licence in `ASSET_LICENSES.md` before the model is used. No
   ripped game content, whatever the uploader claims.
2. **Convert with a script** in `tools/export_*.py` (repeatable; run Blender with `--factory-startup
   --disable-autoexec`, since a downloaded .blend can contain scripts).
3. **Export only meshes:** no lights, no cameras, no helper empties that matter.
4. **Real scale, metres;** Y-up is done by the glTF exporter (don't rotate again in Godot).
5. **Origin where it is used:** at the soles for characters, at the pistol grip for weapons, on the ground for props.
6. **Triangle budget** (held weapon about 15k; check `docs/PERFORMANCE_BUDGETS.md`) and textures at the size the
   phone can afford.
7. Look at it in the game, not only in Blender.

## Entries

### Blender lamps in a .glb turned the game white (2026-10-29)
- See [BUILDINGS.md](BUILDINGS.md). Untick lights in the exporter, and strip `Light3D` nodes in the loader anyway.

### Add-on that downloaded the AK-47 was a look-alike (2026-10-29)
- The installed "BlenderKit" add-on names itself "Blendkit" and talks to blendkit.com, not blenderkit.com.
- **Rule:** check where an asset really came from; until then its licence is "not confirmed" in
  `ASSET_LICENSES.md` and it must be replaced before any public release if it can't be confirmed.

### Ripped content rejected (2026-10-25)
- McLaren F1 (built from NFS/Forza assets) and the "Chubby magic girl" (Daz and Unreal parts) were rejected. A
  model's own files (info.txt, metadata, action names) often reveal where it came from: read them.
