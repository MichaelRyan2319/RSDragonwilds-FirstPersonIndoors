-- First Person Indoors - settings
-- Edit the values below, then restart the game.

return {
    -- Key that toggles first person. Letters ("Z"), function keys ("F5"), etc.
    -- Z is not bound to anything in the game's default controls.
    ToggleKey = "Z",

    -- Optional modifier keys that must be held with ToggleKey, e.g. { "CONTROL" } or { "SHIFT" }.
    ToggleModifiers = {},

    -- Field of view in first person, in degrees. The game uses 75 in third person.
    -- 0 = keep the game's FOV. Bow aiming still zooms in by the same proportion.
    -- Once you move the in-game slider (below), its saved value is used instead;
    -- delete Scripts/saved_fov.txt to go back to this number.
    FirstPersonFOV = 90,

    -- Adds a "First Person FOV" slider to Settings > Gameplay, under Camera Lag.
    -- Changes apply straight away, even while in first person.
    FOVSlider = true,
    FOVSliderMin = 60,
    FOVSliderMax = 120,

    -- Camera shake strength in first person. 1 = normal, 0.5 = half, 0 = off.
    -- (The game's own "Screen Shake" option still turns shake off completely.)
    CameraShakeScale = 1.0,

    -- Where the camera sits:
    --   "head"    = follows your character's head bone (most immersive; moves with animations)
    --   "capsule" = fixed eye height above your character (steadier; doesn't bob or crouch)
    AttachTo = "head",

    -- Eye position relative to the head (centimetres). Raise EyeForwardOffset if you can
    -- see the inside of your own collar; lower it if the camera pokes through walls.
    EyeForwardOffset = 10,
    EyeUpOffset = 6,

    -- Your body turns with the camera, instantly, like a normal first-person game.
    -- false = the game's usual turning (body faces the way you walk).
    BodyFacesCamera = true,

    -- Temporarily go back to third person while sitting/sleeping or riding.
    ThirdPersonWhileResting = true,
    ThirdPersonWhileMounted = true,

    -- Indoors-only mode. false = first person works anywhere.
    -- true = first person only while sheltered (the game's "Sheltered" HUD icon),
    --        switching back to third person when you walk outside.
    IndoorsOnly = false,

    -- These only matter when IndoorsOnly = true:
    -- Come back to first person automatically when you walk back indoors.
    ResumeWhenBackIndoors = true,
    -- Only count player-built buildings as indoors (not caves, ruins, etc.).
    RequirePlayerBuilding = false,
    -- How long you must be outside before switching back (ms); stops doorway flicker.
    OutdoorGraceMs = 1000,
    -- How long you must be back inside before first person resumes (ms).
    IndoorDelayMs = 500,

    -- Character parts hidden from your own view in first person (others still see them).
    HideComponents = { "HeadMesh", "HairZone1Mesh", "FacialHairZone1Mesh", "OutfitHeadMesh", "InvisHairMesh" },
    -- Any other attached part whose name contains one of these words is hidden too.
    HideNamePatterns = { "Head", "Hair", "Helm", "Hood", "Hat", "Beard", "Mask" },

    -- Write extra detail to ue4ss/UE4SS.log (useful if something isn't working).
    DebugLogging = false,
}
