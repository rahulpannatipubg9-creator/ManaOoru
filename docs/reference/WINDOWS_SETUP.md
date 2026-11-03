# Running MANA OORU on Windows

Windows has not been a tested platform for this project. These are the steps that worked on a Dell Latitude 5520
(i7-1165G7, Iris Xe, 16 GB) with the official Godot 4.7.2 build.

## Install

1. Download `Godot_v4.7.2-stable_win64.exe.zip` from the Godot GitHub releases and check it against `SHA512-SUMS.txt`.
2. Unpack it anywhere. An empty file named `._sc_` beside the exe makes editor data stay in that folder.

Godot opened a window here using OpenGL 3.3 on Iris Xe. Game logs still go to
`%APPDATA%\Godot\app_userdata\MANA OORU`.

## The Blender blocker

The repo tracks four `.blend` files:

- `Godavarikhani_Bridge_3D/Godavarikhani_Bridge.blend`
- `Godavarikhani_Bridge_3D/Godavarikhani_Bridge_Test.blend`
- `assets/models/haathgaadi/haathgaadi.blend`
- `assets/models/stadium/jawaharlal_stadium.blend`

Without a Blender path set, headless import prints `Blender path is invalid or not set` and then imports nothing:
0 of the `.glb` models were imported. The game then reports models as missing even though the files exist. With
the `.blend` files moved out, all 48 of 48 models imported.

Setting `filesystem/import/blender/enabled=false` in `override.cfg` did not fix it.

Local workaround used on this machine (nothing committed):

```sh
git update-index --skip-worktree <file>   # for each .blend and .blend.import
mv <file> ../tools/blend-stash/
```

To undo, move the files back and run `git update-index --no-skip-worktree <file>`.

The proper fix is listed in `ASSETS_AND_LICENSES.md`: keep `.blend` sources out of the Godot project folder, or
add a `.gdignore` to a dedicated source folder.

## Import and run

```sh
godot --headless --import      # README's --editor --quit is not enough for a full import
godot --path .                 # run the game
```

A zero exit code from Godot does not mean the game worked. With broken scripts it still exits 0, so read the log
for `SCRIPT ERROR` and `Failed to load script`.

## Line endings

Git here has `core.autocrlf=true`. After an import, Godot rewrites `.import` files and Git lists them as modified,
though the diff is empty. Do not commit them.
