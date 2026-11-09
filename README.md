# First Person for RuneScape: Dragonwilds

A UE4SS Lua mod for RuneScape: Dragonwilds. Press **Z** to switch between first
person and the normal third-person camera.

- Works anywhere. Set `IndoorsOnly = true` in `config.lua` to allow it only while
  sheltered.
- Your body turns with the camera, like a normal first-person game.
- Wider field of view in first person (90 by default). The mod adds a "First Person
  FOV" slider to Settings > Gameplay, under Camera Lag. Camera shake strength is
  adjustable too.
- Switches back to third person while you rest, sleep or ride, then returns.
- Client-side only. Other players and servers don't need it.
- Doesn't change any world settings, so achievements keep working.
- Your own head and helmet are hidden from your view only. Other people still see
  them.

Built for game build 26162923 (Unreal Engine 5.6) with UE4SS v3.0.1-1217.

## Requirements

- [UE4SS for RuneScape: Dragonwilds](https://github.com/MichaelRyan2319/RSDragonwilds-UE4SS).
  Any other UE4SS v3 install works too.

## Install with Mod Loader

[Mod Loader](https://github.com/MichaelRyan2319/ModLoader) installs the mod and
keeps it up to date.

1. **Add game** and pick RuneScape: Dragonwilds. Mod Loader 1.0.1 or later sets
   the mods folder to the game's inner `RSDragonwilds` folder (the one with
   `Binaries` and `Content` in it). If you added the game with an older version,
   edit it and choose that folder.
2. **Add mod** `MichaelRyan2319/RSDragonwilds-UE4SS`, then
   `MichaelRyan2319/RSDragonwilds-FirstPersonIndoors`.
3. Start the game and press Z in-game.

## Install by hand

1. Install UE4SS (see Requirements).
2. Download `FirstPersonIndoors.zip` from the [Releases](../../releases) page.
   In Steam, right-click RuneScape: Dragonwilds > Manage > Browse local files,
   then open the `RSDragonwilds` folder (the one with `Binaries` and `Content`
   in it) and extract the zip there. The mod ends up in
   `Binaries\Win64\ue4ss\Mods\FirstPersonIndoors`.
3. Start the game and press Z in-game.

The mod folder contains `enabled.txt`, so UE4SS loads it without any change to
`mods.txt`. To install from this repo instead of a release, copy the
`FirstPersonIndoors` folder into `Win64\ue4ss\Mods\`.

## Settings

Edit `Win64\ue4ss\Mods\FirstPersonIndoors\Scripts\config.lua` in Notepad, then
restart the game. The main options:

| Setting | Default | What it does |
| --- | --- | --- |
| `ToggleKey` | `"Z"` | The key that switches the camera (Z is unbound in the game's controls) |
| `FirstPersonFOV` | `90` | First-person field of view; `0` keeps the game's 75. The in-game slider overrides this once you move it. |
| `CameraShakeScale` | `1.0` | `1` = normal, `0.5` = half, `0` = off |
| `AttachTo` | `"head"` | `"capsule"` gives a steadier camera that doesn't bob |
| `BodyFacesCamera` | `true` | `false` keeps the game's usual turning |
| `IndoorsOnly` | `false` | `true` = first person only while sheltered |

`config.lua` lists the rest, with comments.

## How it works

- The camera is attached to the head bone, not pulled in by shortening the spring
  arm. The game's camera controller resets the arm length from its camera
  profiles every tick.
- Head, hair, beard and helmet meshes are set to `OwnerNoSee`.
- Body facing sets the pawn's `bUseControllerRotationYaw` and turns off the
  movement component's `bOrientRotationToMovement` and
  `bUseControllerDesiredRotation`. These flags are re-applied every 100 ms
  because the game changes them itself (when aiming, for example). In someone
  else's world, the host still turns your character the usual way for everyone
  else.
- FOV: every `CameraProfile.FOV` is scaled by the same ratio, so bow-aim zoom
  and the sprint FOV change still work.
- The settings slider is a copy of the game's own `WBP_Settings_Slider_C`. It is
  added when a `SettingsGameplayWidget` is created (`NotifyOnNewObject`) and is
  polled for changes. Its value is saved to `Scripts/saved_fov.txt`.
- Camera shake goes through the camera manager's shake modifier `Alpha`.
- Indoors detection reads `CharacterShelterComponent.CurrentShelterTag`
  (`Player.Status.Sheltered[.BaseBuilding]`), the same replicated value that
  drives the "Sheltered" HUD icon.
- Everything it changes is restored when you leave first person, die or quit to
  the menu.

### Achievements

The game skips achievement unlocks only in Creative and Custom worlds. This mod
never touches world difficulty or world settings. It changes only the local
camera and what your own screen draws. The game's mod check (`CheckForMods`)
logs a warning and marks the world as modded for people joining, but
achievements still unlocked in testing.

## Troubleshooting

The log is `Win64\ue4ss\UE4SS.log`. Lines from this mod start with
`[FirstPersonIndoors]`. Set `DebugLogging = true` in `config.lua` for more
detail.

## Uninstall

Delete `Win64\ue4ss\Mods\FirstPersonIndoors`. To remove UE4SS as well, delete
`dwmapi.dll` and the `ue4ss` folder from Win64.

## Credits

UE4SS is made by the UE4SS team ([RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS),
MIT licence).
