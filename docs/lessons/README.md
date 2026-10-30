# Lessons: mistakes we have already made

Reference files so the same mistake is not made twice. **Read the file for the area you are about to touch
before you start, and add an entry the moment you fix a mistake.** A fix without an entry here is not done.

| Area | File |
|---|---|
| Characters in general (rigs, poses, scale, swapping the player model) | [CHARACTERS.md](CHARACTERS.md) |
| The player (Rahul) | [characters/PLAYER_RAHUL.md](characters/PLAYER_RAHUL.md) |
| Remote players in squad / Team Deathmatch | [characters/REMOTE_PLAYERS.md](characters/REMOTE_PLAYERS.md) |
| Test-only lady character | [characters/TEST_LADY.md](characters/TEST_LADY.md) |
| Vehicles: seats, getting in and out, driving pose, physics | [VEHICLES.md](VEHICLES.md) |
| Weapons: rifles, pickups, hit claims | [WEAPONS.md](WEAPONS.md) |
| Buildings, shops, signs, landmarks (the bridge too) | [BUILDINGS.md](BUILDINGS.md) |
| Trees, ground cover, props, pickups and anything placed on the ground | [TREES_AND_PROPS.md](TREES_AND_PROPS.md) |
| Bringing any model into the game (Blender, glTF, downloads, licences) | [IMPORTING_MODELS.md](IMPORTING_MODELS.md) |
| Multiplayer: synced state, protocol version | [MULTIPLAYER.md](MULTIPLAYER.md) |
| Tests, captures, tools and working alongside other sessions | [TESTING_AND_TOOLS.md](TESTING_AND_TOOLS.md) |

## How to write an entry

Newest first inside each file. Keep it short and concrete: name the file, the number, the bone.

```markdown
### <What went wrong, in a few words> (YYYY-MM-DD)
- **Symptom:** what the player saw.
- **Cause:** the actual reason, with the file and function.
- **Rule:** what to do instead from now on.
- **Check:** the test, probe or render that proves it (and would catch it again).
```

When an entry turns out to be wrong or outdated, correct it in place and add "(corrected YYYY-MM-DD)"
rather than leaving two versions. A new kind of asset (a new character, a new vehicle class) gets its own
file in the matching folder, linked from the table above.
