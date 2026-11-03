# MANA OORU UI design

The rule set for every screen. Shared values live in `scripts/ui/ui_theme.gd`; do not hard-code colours, fonts or
sizes elsewhere.

## The problem today

- A debug panel with position, status and key help stays on screen.
- About 20 touch buttons show at once, plus Squad, Bridge and Settings buttons in fixed spots. One of them renders as
  a tall bar over the compass.
- Three lines of status text with key hints, an always-on prompt, a clock bar, and toasts on top of each other.
- Each screen styles itself, so nothing matches. Emoji stand in for icons.
- The window is blank for about 2.5 minutes on start-up, with no title screen.

## Principles, and where they come from

| Principle | Reference | What it means here |
|---|---|---|
| The town is the star | GTA V, Red Dead Redemption 2 | In calm walking or driving, show only the minimap and whatever is changing |
| Show it when it matters | GTA V hides bars until needed; Metroid Prime | Health, ammo and wanted appear on change or in action, then fade |
| One corner per job | GTA V, Forza Horizon | Map and vitals bottom-left, weapon bottom-right, speed bottom-right when driving, objective top-right |
| One action at a time | Genshin Impact, Zelda: Breath of the Wild | One prompt pill: `[E] Enter Thar`. Silence when nothing is nearby |
| Few buttons, in thumb reach | BGMI, COD Mobile, Genshin Impact | Touch shows only what this moment needs; the rest goes in a wheel |
| Rare actions go in a wheel or menu | GTA V weapon wheel | Medkit, grenade, surrender, avatar and radio live in a hold-to-open wheel |
| Layouts are the player's | BGMI, COD Mobile | Keep the existing editor; sensible defaults first |
| Teach by doing | Forza Horizon | A hint shows once, when first relevant, then never again |

The web search found mostly mod pages and low-quality guides, so these principles rest on how those games are widely
known to work, not on published design documents. Check them against play-testing.

## Layout at 1280x720

```
 ┌───────────────────────────────────────────────────────────────┐
 │ N ── NE ── E  compass strip (top centre, thin)      objective │
 │                                                     + distance│
 │ wanted stars (only when wanted)                               │
 │                                                               │
 │                                                               │
 │                     [E] Enter Thar  (centre, lower third)     │
 │ ┌───────┐                                                     │
 │ │minimap│                                  rifle  24 / 120    │
 │ └───────┘  health / armour bars            or  72 km/h  D3    │
 └───────────────────────────────────────────────────────────────┘
```

## HUD states

| State | Shown |
|---|---|
| Calm on foot | Minimap, compass |
| Near something | + one prompt pill |
| Hurt | + vitals, which fade after 4 s at full health |
| Rifle out | + ammo, crosshair, vitals |
| Driving | + speed, gear, fuel only when low |
| Wanted | + stars |
| On a job | + objective and timer, top right |
| Coins change | Small `+5` near the minimap, then fades |

Never shown in play: coordinates, status text, key lists, "offline", or an empty prompt.

## Touch

| State | Buttons |
|---|---|
| Calm on foot | Stick, jump, run, context action, wheel, map through minimap |
| Rifle out | + fire, aim, reload, crouch, swap when two rifles are owned |
| Driving | Stick, brake, handbrake or gears if manual, exit, camera |
| Flying | Stick, up, down, exit |

All else goes in the wheel. Icons drawn with vector shapes or Noto glyphs, not emoji. Targets are at least 48 units.

## Menus

- Esc or the menu button opens one pause menu: Resume, Map, Activities, Squad, Settings, Quit.
- Settings keeps tabs: Controls, Graphics, Audio, Time & Weather. Touch-only settings hide on desktop.
- Debug tools such as bridge teleport and the sketch map are hidden behind a developer flag.
- One primary button per screen. Esc always goes back. Everything works by keyboard, mouse, and touch.

## Text

- Sentence case, except short labels. Prompts at most 4 words, toasts at most 8.
- One toast at a time; queue the rest. Each lasts 3 s.
- Key hints appear only inside prompts or the controls help page.
- Use the Noto fonts with the Telugu fallback. Keep user-visible strings ready for translation later.

## Motion

Fades of 0.12 to 0.2 s. No bouncing. Nothing moves when the game is paused other than the menu opening.

## Start-up

Boot scene → title screen (Continue, New Game, Squad, Settings, Credits, Quit) → loading screen with real progress
and a tip → the game. Credits include the map data attributions that `ASSETS_AND_LICENSES.md` calls for.

## Sources

- [Heads-Up Display, GTA Wiki](https://gta.fandom.com/wiki/Heads-Up_Display)
- [Radial menus in game design](https://300mind.studio/blog/radial-menus-in-game-design/)
- [UX and UI in game design: HUD, inventory and menus](https://medium.com/@brdelfino.work/ux-and-ui-in-game-design-exploring-hud-inventory-and-menus-5d8c189deb65)
- [Genshin Impact is an evolution for mobile design](https://game-wisdom.com/?p=25386)
- [Best HUD settings for Apex Legends Mobile](https://progameguides.com/apex-legends-mobile/best-hud-settings-for-apex-legends-mobile/)
- [Apex Legends Mobile: best four-finger control layout](https://www.pocketgamer.com/apex-legends-mobile/best-four-finger-control-layout)
- [How to add a loading screen with a progress bar in Godot 4](https://dev.to/saltmire/how-to-add-a-loading-screen-with-a-progress-bar-in-godot-4-3pi7)
