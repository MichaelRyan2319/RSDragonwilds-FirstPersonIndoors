--[[
    First Person Indoors - RuneScape: Dragonwilds (UE4SS Lua mod)

    Press the toggle key (default Z) to switch between first and third person.
    Optional: set IndoorsOnly = true in config.lua to allow first person only while
    sheltered (the game's "Sheltered" status icon), switching back outside.

    The first-person FOV can also be set in-game: Settings > Gameplay has a
    "First Person FOV" slider (added by this mod, saved to saved_fov.txt).

    Achievements: this mod only moves the local camera and hides your own head from
    your own view. It never changes world difficulty or other world settings, and
    those settings are what the game checks before it unlocks achievements.

    Settings live in config.lua next to this file.
]]

local UEHelpers = require("UEHelpers")

local MOD = "[FirstPersonIndoors] "
local UPDATE_MS = 100
local MAINTAIN_EVERY_MS = 1000
local CONTROLLER_RETRY_MS = 1000

-- EAttachmentRule
local KEEP_RELATIVE, KEEP_WORLD, SNAP_TO_TARGET = 0, 1, 2

------------------------------------------------------------------------ config

local Defaults = {
    ToggleKey = "Z",
    ToggleModifiers = {},
    IndoorsOnly = false,
    ResumeWhenBackIndoors = true,
    RequirePlayerBuilding = false,
    OutdoorGraceMs = 1000,
    IndoorDelayMs = 500,
    AttachTo = "head",
    HeadSocket = "head",
    EyeForwardOffset = 10,
    EyeUpOffset = 6,
    BodyFacesCamera = true,
    FirstPersonFOV = 90,
    FOVSlider = true,
    FOVSliderMin = 60,
    FOVSliderMax = 120,
    CameraShakeScale = 1.0,
    ThirdPersonWhileResting = true,
    ThirdPersonWhileMounted = true,
    HideComponents = { "HeadMesh", "HairZone1Mesh", "FacialHairZone1Mesh", "OutfitHeadMesh", "InvisHairMesh" },
    HideNamePatterns = { "Head", "Hair", "Helm", "Hood", "Hat", "Beard", "Mask" },
    DebugLogging = false,
}

local Config = {}
for k, v in pairs(Defaults) do Config[k] = v end
do
    local ok, user = pcall(require, "config")
    if ok and type(user) == "table" then
        for k, v in pairs(user) do Config[k] = v end
    elseif not ok then
        print(MOD .. "config.lua could not be loaded, using defaults: " .. tostring(user) .. "\n")
    end
end

local function Log(fmt, ...)
    print(MOD .. string.format(fmt, ...) .. "\n")
end

local function Debug(fmt, ...)
    if Config.DebugLogging then Log(fmt, ...) end
end

-- The settings-menu slider saves its value here; it wins over FirstPersonFOV in
-- config.lua. Delete the file to go back to the config.lua value.
local FOV_FILE = (function()
    -- Level 1 is this function, so its source is main.lua's own path.
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local source = info and info.source or ""
    local dir = source:match("^@(.*[\\/])") or "ue4ss/Mods/FirstPersonIndoors/Scripts/"
    return dir .. "saved_fov.txt"
end)()

local function LoadSavedFOV()
    local f = io.open(FOV_FILE, "r")
    if f == nil then return end
    local value = tonumber(f:read("*l") or "")
    f:close()
    if value and value >= 30 and value <= 150 then
        Config.FirstPersonFOV = value
    end
end

local function SaveFOV(value)
    local f, err = io.open(FOV_FILE, "w")
    if f == nil then
        Log("Could not save the FOV setting to %s: %s", FOV_FILE, tostring(err))
        return
    end
    f:write(string.format("%d\n", value))
    f:close()
end

if Config.FOVSlider then LoadSavedFOV() end

------------------------------------------------------------------- safe access

local function Valid(obj)
    if obj == nil then return false end
    local ok, res = pcall(function() return obj:IsValid() end)
    return ok and res == true
end

local function Get(obj, prop)
    local ok, value = pcall(function() return obj[prop] end)
    if ok then return value end
    return nil
end

local function Set(obj, prop, value)
    local ok, err = pcall(function() obj[prop] = value end)
    if not ok then Debug("Could not set %s: %s", prop, tostring(err)) end
    return ok
end

local function Call(obj, fn, ...)
    local args = table.pack(...)
    local ok, res = pcall(function() return obj[fn](obj, table.unpack(args, 1, args.n)) end)
    if not ok then Debug("%s failed: %s", fn, tostring(res)) end
    return ok, res
end

local function Address(obj)
    local ok, addr = pcall(function() return obj:GetAddress() end)
    if ok then return addr end
    return nil
end

local function Vec(x, y, z) return { X = x, Y = y, Z = z } end
local function CopyVec(v) return Vec(v.X, v.Y, v.Z) end
local function CopyRot(r) return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end
local ZERO_ROT = { Pitch = 0, Yaw = 0, Roll = 0 }

------------------------------------------------------------------- game state

local CachedController = nil
local ControllerRetryMs = 0
local CharacterClass = nil

local function IsPlayerCharacter(pawn)
    if not Valid(CharacterClass) then
        CharacterClass = StaticFindObject("/Script/Dominion.DominionPlayerCharacter")
    end
    if Valid(CharacterClass) then
        local ok, result = pcall(function() return pawn:IsA(CharacterClass) end)
        if ok then return result == true end
    end
    return Valid(Get(pawn, "FollowCamera"))
end

local function GetLocalPawn()
    if not Valid(CachedController) then
        CachedController = nil
        if ControllerRetryMs > 0 then return nil end
        ControllerRetryMs = CONTROLLER_RETRY_MS  -- FindAllOf is slow; don't run it every tick
        local pc = UEHelpers.GetPlayerController()
        if not Valid(pc) then return nil end
        CachedController = pc
    end
    local pawn = Get(CachedController, "Pawn")
    -- Only the in-world player character has these; menus and spectating don't.
    if Valid(pawn) and IsPlayerCharacter(pawn) and Valid(Get(pawn, "FollowCamera")) and Valid(Get(pawn, "Mesh")) then
        return pawn
    end
    return nil
end

local function ShelterTag(pawn)
    local comp = Get(pawn, "CharacterShelterComponent")
    if not Valid(comp) then comp = Get(pawn, "BP_Components_CharacterShelter") end
    if not Valid(comp) then return nil end
    local tag = Get(comp, "CurrentShelterTag")
    local name = tag and Get(tag, "TagName")
    if name == nil then return nil end
    local ok, text = pcall(function() return name:ToString() end)
    if ok then return text end
    return nil
end

-- The game sets CurrentShelterTag to Player.Status.Sheltered (or its child
-- Player.Status.Sheltered.BaseBuilding inside player-built structures). It is the
-- same value that drives the "Sheltered" HUD icon, and it is replicated, so this
-- also works when you join someone else's world.
local function IsIndoors(pawn)
    local tag = ShelterTag(pawn)
    if tag == nil then return false end
    if Config.RequirePlayerBuilding then
        return tag == "Player.Status.Sheltered.BaseBuilding"
    end
    return tag == "Player.Status.Sheltered" or tag:sub(1, 24) == "Player.Status.Sheltered."
end

-- Whether first person is allowed where the player is standing right now.
local function Allowed(pawn)
    if not Config.IndoorsOnly then return true end
    return IsIndoors(pawn)
end

local function SuspendReason(pawn)
    if Config.ThirdPersonWhileResting then
        local rest = Get(pawn, "PlayerRestComponent")
        if Valid(rest) then
            local ok, resting = Call(rest, "IsResting")
            if ok and resting == true then return "resting" end
            local ok2, sleeping = Call(rest, "GetIsSleeping")
            if ok2 and sleeping == true then return "sleeping" end
        end
    end
    if Config.ThirdPersonWhileMounted then
        local mount = Get(pawn, "MountComponent")
        if Valid(mount) then
            local ok, state = Call(mount, "GetMountState")
            -- EMountState: None, Dismounted, Mounting, Mounted, Dismounting
            if ok and type(state) == "number" and state >= 2 then return "mounted" end
        end
    end
    return nil
end

------------------------------------------------------------------ camera work

local State = {
    wantFirstPerson = false,  -- the player's choice (toggle key)
    active = false,           -- camera currently in first person
    saved = nil,              -- what to restore when leaving first person
    pawnAddress = nil,
    pawn = nil,
    indoorMs = 0,
    outdoorMs = 0,
    maintainMs = 0,
}

local function HeadOffset(pawn, mesh)
    local f, u = Config.EyeForwardOffset or 0, Config.EyeUpOffset or 0
    if f == 0 and u == 0 then return Vec(0, 0, 0) end
    -- The offset is wanted in the character's forward/up directions, but a component
    -- attached to a bone is positioned in that bone's space, so convert it.
    local ok, result = pcall(function()
        local kml = UEHelpers.GetKismetMathLibrary()
        local fwd = pawn:GetActorForwardVector()
        local up = pawn:GetActorUpVector()
        local world = Vec(fwd.X * f + up.X * u, fwd.Y * f + up.Y * u, fwd.Z * f + up.Z * u)
        local boneRot = CopyRot(mesh:GetSocketRotation(FName(Config.HeadSocket)))
        local inBone = kml:LessLess_VectorRotator(world, boneRot)
        local scale = mesh:K2_GetComponentScale()
        local s = (scale and scale.X and scale.X ~= 0) and scale.X or 1
        return Vec(inBone.X / s, inBone.Y / s, inBone.Z / s)
    end)
    if ok and result then return result end
    Log("Could not work out the eye offset (%s); using the head bone position.", tostring(result))
    return Vec(0, 0, 0)
end

local function HideHeadParts(pawn)
    local saved = State.saved
    local function hide(comp)
        if not Valid(comp) then return end
        local key = Address(comp)
        if key == nil or saved.hidden[key] then return end
        local was = Get(comp, "bOwnerNoSee") == true
        local ok = Call(comp, "SetOwnerNoSee", true)
        if ok then
            saved.hidden[key] = { comp = comp, was = was }
            if Config.DebugLogging then
                local okName, name = pcall(function() return comp:GetFName():ToString() end)
                Debug("Hid %s", okName and name or "?")
            end
        end
    end

    for _, prop in ipairs(Config.HideComponents or {}) do
        hide(Get(pawn, prop))
    end

    local patterns = Config.HideNamePatterns or {}
    if #patterns == 0 then return end
    local primitiveClass = StaticFindObject("/Script/Engine.PrimitiveComponent")
    if not Valid(primitiveClass) then return end
    local ok, comps = Call(pawn, "K2_GetComponentsByClass", primitiveClass)
    if not ok or comps == nil then return end
    pcall(function()
        comps:ForEach(function(_, element)
            local comp = element:get()
            if Valid(comp) then
                local name = comp:GetFName():ToString():lower()
                for _, pattern in ipairs(patterns) do
                    if name:find(pattern:lower(), 1, true) then
                        hide(comp)
                        break
                    end
                end
            end
        end)
    end)
end

-- Body facing: lock the character's yaw to the camera every frame, the way normal
-- first-person games do (APawn::bUseControllerRotationYaw). The movement
-- component's own turning is switched off so it can't pull the body back towards
-- the direction you walk. Re-applied every update because the game changes these
-- flags itself, e.g. when aiming or entering combat.
local function ApplyFacing(saved)
    if saved.facingPawn and Valid(saved.facingPawn) then
        Set(saved.facingPawn, "bUseControllerRotationYaw", true)
    end
    if saved.movement and Valid(saved.movement) then
        Set(saved.movement, "bOrientRotationToMovement", false)
        Set(saved.movement, "bUseControllerDesiredRotation", false)
    end
end

-- FOV: the game's camera controller blends the camera's FOV towards the active
-- camera profile (75 walking, 77 sprinting, 60-65 aiming a bow, ...). Scaling every
-- profile by the same ratio gives the chosen FOV while keeping those changes.
local function ScaleCameraProfiles(saved)
    if saved.fovRatio == nil then return end
    local ok, profiles = pcall(FindAllOf, "CameraProfile")
    if not ok or type(profiles) ~= "table" then return end
    for _, profile in ipairs(profiles) do
        local key = Valid(profile) and Address(profile)
        if key and not saved.profiles[key] then
            local fov = Get(profile, "FOV")
            if type(fov) == "number" and fov > 0 then
                saved.profiles[key] = { obj = profile, fov = fov }
                Set(profile, "FOV", fov * saved.fovRatio)
            end
        end
    end
end

local function ApplyFOV(pawn, saved)
    local target = tonumber(Config.FirstPersonFOV) or 0
    if target <= 0 then return end
    target = math.max(30, math.min(150, target))
    local base = 75
    local controller = Get(pawn, "PlayerCameraController")
    local default = Valid(controller) and Get(controller, "DefaultCameraProfile")
    local defaultFov = Valid(default) and Get(default, "FOV")
    if type(defaultFov) == "number" and defaultFov > 0 then base = defaultFov end
    saved.fovRatio = target / base
    saved.cameraFov = Get(saved.camera, "FieldOfView")
    ScaleCameraProfiles(saved)
    Call(saved.camera, "SetFieldOfView", target)  -- take effect now, not at the next blend
end

local function RestoreFOV(saved)
    for _, entry in pairs(saved.profiles) do
        if Valid(entry.obj) then Set(entry.obj, "FOV", entry.fov) end
    end
    if saved.fovRatio and type(saved.cameraFov) == "number" and Valid(saved.camera) then
        Call(saved.camera, "SetFieldOfView", saved.cameraFov)
    end
end

-- Camera shake: every shake is played through the camera manager's shake modifier,
-- and that modifier's Alpha multiplies all of them. The engine eases Alpha back to 1
-- over AlphaInTime seconds each frame, so a huge AlphaInTime keeps our value.
local function ApplyShakeScale(saved)
    local scale = tonumber(Config.CameraShakeScale)
    if scale == nil or scale == 1 then return end
    scale = math.max(0, math.min(5, scale))
    local modifier = saved.shakeModifier
    if not Valid(modifier) then
        local manager = Valid(CachedController) and Get(CachedController, "PlayerCameraManager")
        modifier = Valid(manager) and Get(manager, "CachedCameraShakeMod")
        if not Valid(modifier) then
            Debug("Camera shake modifier not found.")
            return
        end
        saved.shakeModifier = modifier
        saved.shakeAlphaInTime = Get(modifier, "AlphaInTime")
    end
    Set(modifier, "AlphaInTime", 1.0e9)
    Set(modifier, "Alpha", scale)
end

local function RestoreShakeScale(saved)
    local modifier = saved.shakeModifier
    if not Valid(modifier) then return end
    local alphaIn = saved.shakeAlphaInTime
    Set(modifier, "AlphaInTime", type(alphaIn) == "number" and alphaIn or 0)
    Set(modifier, "Alpha", 1)
end

local function EnterFirstPerson(pawn)
    local camera = Get(pawn, "FollowCamera")
    local mesh = Get(pawn, "Mesh")
    if not Valid(camera) or not Valid(mesh) then
        Log("Player camera not found; staying in third person.")
        return false
    end

    local ok1, parent = Call(camera, "GetAttachParent")
    local ok2, socket = Call(camera, "GetAttachSocketName")
    local relLoc, relRot = Get(camera, "RelativeLocation"), Get(camera, "RelativeRotation")
    if not (ok1 and Valid(parent) and ok2 and relLoc and relRot) then
        Log("Could not read the current camera setup; staying in third person.")
        return false
    end

    local saved = {
        hidden = {},
        profiles = {},
        camera = camera,
        parent = parent,
        socket = socket,
        relLoc = CopyVec(relLoc),
        relRot = CopyRot(relRot),
        usePawnControlRotation = Get(camera, "bUsePawnControlRotation") == true,
    }

    local target, socketName, location
    if Config.AttachTo == "capsule" then
        target = Get(pawn, "RootComponent")
        socketName = FName("None")
        local eye = Get(pawn, "BaseEyeHeight")
        location = Vec(Config.EyeForwardOffset or 0, 0, (type(eye) == "number" and eye or 64) + (Config.EyeUpOffset or 0))
    else
        target = mesh
        socketName = FName(Config.HeadSocket)
        location = HeadOffset(pawn, mesh)
    end
    if not Valid(target) then
        Log("Nothing to attach the camera to; staying in third person.")
        return false
    end

    local attached, result = Call(camera, "K2_AttachToComponent", target, socketName,
        SNAP_TO_TARGET, SNAP_TO_TARGET, KEEP_WORLD, false)
    if not attached or result == false then
        Log("Attaching the camera failed; staying in third person.")
        Call(camera, "K2_AttachToComponent", parent, socket, KEEP_RELATIVE, KEEP_RELATIVE, KEEP_RELATIVE, false)
        return false
    end
    Call(camera, "K2_SetRelativeLocation", location, false, {}, false)
    Call(camera, "K2_SetRelativeRotation", ZERO_ROT, false, {}, false)
    Set(camera, "bUsePawnControlRotation", true)
    saved.target = target

    if Config.BodyFacesCamera then
        saved.facingPawn = pawn
        saved.useControllerYaw = Get(pawn, "bUseControllerRotationYaw")
        local movement = Get(pawn, "CharacterMovement")
        if Valid(movement) then
            saved.movement = movement
            saved.orientToMovement = Get(movement, "bOrientRotationToMovement")
            saved.useDesiredRotation = Get(movement, "bUseControllerDesiredRotation")
        end
    end

    State.saved = saved
    State.active = true
    State.maintainMs = 0
    State.maintainCount = 0
    HideHeadParts(pawn)
    ApplyFacing(saved)
    ApplyFOV(pawn, saved)
    ApplyShakeScale(saved)
    Log("First person on.")
    return true
end

local function ExitFirstPerson(reason)
    local saved = State.saved
    State.active = false
    State.saved = nil
    if saved == nil then return end

    for _, entry in pairs(saved.hidden) do
        if Valid(entry.comp) then Call(entry.comp, "SetOwnerNoSee", entry.was) end
    end
    RestoreFOV(saved)
    RestoreShakeScale(saved)

    if saved.facingPawn and Valid(saved.facingPawn) and type(saved.useControllerYaw) == "boolean" then
        Set(saved.facingPawn, "bUseControllerRotationYaw", saved.useControllerYaw)
    end
    if saved.movement and Valid(saved.movement) then
        if type(saved.orientToMovement) == "boolean" then
            Set(saved.movement, "bOrientRotationToMovement", saved.orientToMovement)
        end
        if type(saved.useDesiredRotation) == "boolean" then
            Set(saved.movement, "bUseControllerDesiredRotation", saved.useDesiredRotation)
        end
    end

    local camera = saved.camera
    if Valid(camera) and Valid(saved.parent) then
        Call(camera, "K2_AttachToComponent", saved.parent, saved.socket,
            KEEP_RELATIVE, KEEP_RELATIVE, KEEP_RELATIVE, false)
        Call(camera, "K2_SetRelativeLocation", saved.relLoc, false, {}, false)
        Call(camera, "K2_SetRelativeRotation", saved.relRot, false, {}, false)
        Set(camera, "bUsePawnControlRotation", saved.usePawnControlRotation)
    end
    Log("Third person (%s).", reason)
end

-- Changes the first-person FOV, live if first person is on right now.
local function SetFirstPersonFOV(value)
    Config.FirstPersonFOV = value
    local saved = State.saved
    if State.active and saved and Valid(State.pawn) then
        RestoreFOV(saved)
        saved.profiles = {}
        saved.fovRatio = nil
        ApplyFOV(State.pawn, saved)
    end
end

-- Runs about once a second while in first person: hides parts that were added
-- since (e.g. a newly equipped helmet) and re-applies settings the game may reset.
local function Maintain(pawn)
    local saved = State.saved
    HideHeadParts(pawn)
    ApplyFacing(saved)
    ApplyShakeScale(saved)
    -- Profiles that load later (e.g. the first time you fish) get scaled too.
    -- FindAllOf walks every object, so only do it every 10 seconds.
    State.maintainCount = (State.maintainCount or 0) + 1
    if State.maintainCount % 10 == 0 then ScaleCameraProfiles(saved) end
    local ok, parent = Call(saved.camera, "GetAttachParent")
    if ok and Valid(parent) and Address(parent) ~= Address(saved.target) then
        Debug("Camera was moved by the game; switching off and on again.")
        ExitFirstPerson("camera reset by game")
        EnterFirstPerson(pawn)
    end
end

-------------------------------------------------------- FOV slider in Settings

-- The game's Settings > Gameplay tab (native class SettingsGameplayWidget) has a
-- Camera Lag slider. A second widget of the same class is created, labelled
-- "First Person FOV" and inserted right below it, so it looks and behaves like the
-- game's own sliders. Its value is polled; nothing in the game's settings is changed.

local FOV_LABEL = "First Person FOV"
local SETTINGS_TAB_CLASS = "/Script/Dominion.SettingsGameplayWidget"
local SETTINGS_TAB_TRIES = 600  -- give up on a tab that never finishes building (60 s)
local FOV_SAVE_DELAY_MS = 500

local SettingsTabs = {}   -- address -> { widget, tries }
local FOVSliders = {}     -- address -> { widget, expected }
local PendingSave = nil   -- { value, ms }

local function SliderRange()
    local lo = math.max(30, math.min(149, tonumber(Config.FOVSliderMin) or 60))
    local hi = math.max(lo + 1, math.min(150, tonumber(Config.FOVSliderMax) or 120))
    return lo, hi
end

local function FOVSettingForSlider()
    local lo, hi = SliderRange()
    local value = tonumber(Config.FirstPersonFOV) or 0
    if value <= 0 then value = 75 end  -- 0 means "game default", which is 75
    return math.floor(math.max(lo, math.min(hi, value)) + 0.5)
end

-- Widgets that only exist as templates inside the widget blueprint (or the class
-- default object) are created too; they must never be touched.
local function IsTemplate(obj)
    local ok, name = pcall(function() return obj:GetFullName() end)
    if not ok or type(name) ~= "string" then return true end
    return name:find("Default__", 1, true) ~= nil or name:find("_C:WidgetTree", 1, true) ~= nil
end

local function SliderValue(slider)
    local ok, value = Call(slider, "GetSliderValue")
    if ok and type(value) == "number" then return value end
    local inner = Get(slider, "InputSlider")
    if Valid(inner) then
        local ok2, value2 = Call(inner, "GetValue")
        if ok2 and type(value2) == "number" then return value2 end
    end
    return nil
end

local function ShowSliderValue(slider, value)
    local ok = Call(slider, "SetCurrentValue", value)
    local now = SliderValue(slider)
    if not ok or now == nil or math.abs(now - value) > 0.5 then
        local inner = Get(slider, "InputSlider")
        if Valid(inner) then Call(inner, "SetValue", value) end
    end
    -- Whichever path ran, make sure the number shown next to the slider matches.
    local text = Get(slider, "SliderValueText")
    if Valid(text) then
        local want = string.format("%d", value)
        local okText, shown = pcall(function() return text:GetText():ToString() end)
        if not okText or shown ~= want then Call(text, "SetText", FText(want)) end
    end
end

-- True while the player is dragging, clicking or (gamepad) focused on the slider,
-- so a change can be told apart from the menu resetting the widget.
local function UserIsUsing(slider)
    for _, widget in ipairs({ Get(slider, "InputSlider"), slider }) do
        if Valid(widget) then
            for _, fn in ipairs({ "HasMouseCapture", "IsHovered", "HasAnyUserFocus", "HasFocusedDescendants" }) do
                local ok, result = Call(widget, fn)
                if ok and result == true then return true end
            end
        end
    end
    return false
end

local function CopySlotLayout(from, to)
    if not (Valid(from) and Valid(to)) then return end
    pcall(function()
        local pad = from.Padding
        if pad then
            Call(to, "SetPadding", { Left = pad.Left, Top = pad.Top, Right = pad.Right, Bottom = pad.Bottom })
        end
    end)
    pcall(function() Call(to, "SetHorizontalAlignment", from.HorizontalAlignment) end)
    pcall(function() Call(to, "SetVerticalAlignment", from.VerticalAlignment) end)
    pcall(function()
        local size = from.Size
        if size then Call(to, "SetSize", { SizeRule = size.SizeRule, Value = size.Value }) end
    end)
end

-- Returns true when finished with this tab (slider added, or it can't be).
local function AddFOVSlider(tab)
    local template = Get(tab, "CameraLagMagnitudeSlider")
    if not Valid(template) then return false end
    local okParent, parent = Call(template, "GetParent")
    if not okParent or not Valid(parent) then return false end

    local library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local okClass, class = pcall(function() return template:GetClass() end)
    if not Valid(library) or not okClass or not Valid(class) then
        Log("Could not find the settings slider widget; the FOV slider was not added.")
        return true
    end
    local okPC, pc = Call(tab, "GetOwningPlayer")
    if not okPC or not Valid(pc) then pc = nil end
    local okCreate, slider = Call(library, "Create", tab, class, pc)
    if not okCreate or not Valid(slider) then
        Log("Could not create the FOV slider.")
        return true
    end

    local lo, hi = SliderRange()
    Set(slider, "InitialMinSliderValue", lo)
    Set(slider, "InitialMaxSliderValue", hi)
    Set(slider, "NumGamepadSliderIncrements", hi - lo)
    Set(slider, "ValueDisplayMultiplier", 1)
    Set(slider, "AmountDecimalPlacesToShow", 0)
    Set(slider, "bShowPostfix", false)
    Set(slider, "bBroadcastUpdateOnSlide", true)
    Set(slider, "LabelText", FText(FOV_LABEL))

    local okIndex, index = Call(parent, "GetChildIndex", template)
    local okAdd, slot = Call(parent, "AddChild", slider)
    if not okAdd then
        Log("Could not add the FOV slider to the settings list.")
        return true
    end
    if okIndex and type(index) == "number" and index >= 0 then
        Call(parent, "ShiftChild", index + 1, slider)
    end
    CopySlotLayout(Get(template, "Slot"), slot)

    Call(slider, "SetLabelText", FText(FOV_LABEL))
    local inner = Get(slider, "InputSlider")
    local okMin = Call(slider, "SetMinSliderValue", lo)
    local okMax = Call(slider, "SetMaxSliderValue", hi)
    if Valid(inner) then
        if not okMin then Call(inner, "SetMinValue", lo) end
        if not okMax then Call(inner, "SetMaxValue", hi) end
        Call(inner, "SetStepSize", 1)
    end

    local value = FOVSettingForSlider()
    ShowSliderValue(slider, value)
    local key = Address(slider)
    if key then FOVSliders[key] = { widget = slider, expected = value } end
    Log("Added the %s slider to Settings > Gameplay.", FOV_LABEL)
    return true
end

local function UpdateSettingsMenu()
    for key, entry in pairs(SettingsTabs) do
        entry.tries = entry.tries + 1
        if not Valid(entry.widget) or entry.tries > SETTINGS_TAB_TRIES or AddFOVSlider(entry.widget) then
            SettingsTabs[key] = nil
        end
    end

    local current = FOVSettingForSlider()
    for key, entry in pairs(FOVSliders) do
        local slider = entry.widget
        if not Valid(slider) then
            FOVSliders[key] = nil
        else
            local value = SliderValue(slider)
            if value and math.abs(value - entry.expected) >= 0.5 then
                if UserIsUsing(slider) then
                    entry.expected = math.floor(value + 0.5)
                    if entry.expected ~= current then
                        SetFirstPersonFOV(entry.expected)
                        current = entry.expected
                        PendingSave = { value = entry.expected, ms = 0 }
                        Debug("First person FOV set to %d.", entry.expected)
                    end
                else
                    ShowSliderValue(slider, entry.expected)  -- the menu reset it; put it back
                end
            elseif entry.expected ~= current and not UserIsUsing(slider) then
                -- Changed in another copy of the menu (main menu vs. in-game).
                entry.expected = current
                ShowSliderValue(slider, current)
            end
        end
    end

    if PendingSave then
        PendingSave.ms = PendingSave.ms + UPDATE_MS
        if PendingSave.ms >= FOV_SAVE_DELAY_MS then
            SaveFOV(PendingSave.value)
            PendingSave = nil
        end
    end
end

local function WatchSettingsMenu()
    if not Config.FOVSlider then return end
    local ok, err = pcall(NotifyOnNewObject, SETTINGS_TAB_CLASS, function(tab)
        if not IsTemplate(tab) then
            local key = Address(tab)
            if key then SettingsTabs[key] = { widget = tab, tries = 0 } end
        end
    end)
    if not ok then
        Log("Settings menu class not found (%s); no FOV slider. FirstPersonFOV in config.lua still works.", tostring(err))
    end
end

--------------------------------------------------------------------- driving

local function Update()
    if ControllerRetryMs > 0 then ControllerRetryMs = ControllerRetryMs - UPDATE_MS end
    if Config.FOVSlider then UpdateSettingsMenu() end

    local pawn = GetLocalPawn()
    local address = pawn and Address(pawn)
    if address ~= State.pawnAddress then
        -- New world, respawn, or back at the menu: the old camera setup no longer applies.
        -- Always restore: camera profiles and the shake modifier outlive the character.
        if State.active then ExitFirstPerson("character changed") end
        State.pawn, State.pawnAddress = pawn, address
        State.indoorMs, State.outdoorMs = 0, 0
    end
    if pawn == nil then return end

    if Allowed(pawn) then
        State.indoorMs, State.outdoorMs = State.indoorMs + UPDATE_MS, 0
    else
        State.indoorMs, State.outdoorMs = 0, State.outdoorMs + UPDATE_MS
    end
    local suspend = SuspendReason(pawn)

    if State.active then
        if suspend then
            ExitFirstPerson(suspend)
        elseif State.outdoorMs >= Config.OutdoorGraceMs then
            ExitFirstPerson("went outside")
            if not Config.ResumeWhenBackIndoors then State.wantFirstPerson = false end
        else
            ApplyFacing(State.saved)
            State.maintainMs = State.maintainMs + UPDATE_MS
            if State.maintainMs >= MAINTAIN_EVERY_MS then
                State.maintainMs = 0
                Maintain(pawn)
            end
        end
    elseif State.wantFirstPerson and not suspend and State.indoorMs >= Config.IndoorDelayMs then
        EnterFirstPerson(pawn)
    end
end

local function Toggle()
    local pawn = GetLocalPawn()
    if pawn == nil then return end

    if State.wantFirstPerson or State.active then
        State.wantFirstPerson = false
        if State.active then ExitFirstPerson("toggled off") end
        Log("First person mode off.")
        return
    end

    if not Allowed(pawn) then
        Log("Not sheltered (shelter tag: %s); IndoorsOnly is on, so first person only works indoors.", tostring(ShelterTag(pawn)))
        return
    end

    State.wantFirstPerson = true
    local suspend = SuspendReason(pawn)
    if suspend then
        Log("First person will start when you are no longer %s.", suspend)
        return
    end
    EnterFirstPerson(pawn)
end

local function Guarded(name, fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then Log("%s error: %s", name, tostring(err)) end
    end
end

local SafeUpdate = Guarded("Update", Update)
local SafeToggle = Guarded("Toggle", Toggle)

--------------------------------------------------------------------- startup

local function CheckGameClasses()
    local character = StaticFindObject("/Script/Dominion.DominionPlayerCharacter")
    if not Valid(character) then
        Log("WARNING: /Script/Dominion.DominionPlayerCharacter not found - a game update may have changed things.")
        return
    end
    local expected = { CameraBoom = false, FollowCamera = false, CharacterShelterComponent = false,
                       HeadMesh = false, PlayerRestComponent = false, MountComponent = false }
    pcall(function()
        character:ForEachProperty(function(property)
            local name = property:GetFName():ToString()
            if expected[name] ~= nil then expected[name] = true end
        end)
    end)
    local missing = {}
    for name, found in pairs(expected) do
        if not found then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        Log("WARNING: player character is missing: %s. Parts of the mod may not work.", table.concat(missing, ", "))
    else
        Debug("Player character layout looks as expected.")
    end
    if Config.IndoorsOnly and not Valid(StaticFindObject("/Script/Dominion.CharacterShelterComponent")) then
        Log("WARNING: CharacterShelterComponent class not found; indoor detection will not work.")
    end
end

local key = Key[tostring(Config.ToggleKey):upper()]
if key == nil then
    Log("Unknown ToggleKey '%s' in config.lua; using Z.", tostring(Config.ToggleKey))
    key = Key.Z
end
local modifiers = {}
for _, name in ipairs(Config.ToggleModifiers or {}) do
    local m = ModifierKey[tostring(name):upper()]
    if m then modifiers[#modifiers + 1] = m else Log("Unknown modifier '%s' ignored.", tostring(name)) end
end

local function OnKey()
    ExecuteInGameThread(SafeToggle)
end
if #modifiers > 0 then
    RegisterKeyBind(key, modifiers, OnKey)
else
    RegisterKeyBind(key, OnKey)
end

local updateQueued = false
LoopAsync(UPDATE_MS, function()
    if not updateQueued then
        updateQueued = true
        ExecuteInGameThread(function()
            updateQueued = false
            SafeUpdate()
        end)
    end
    return false
end)

ExecuteInGameThread(Guarded("Startup check", CheckGameClasses))
WatchSettingsMenu()
Log("Loaded. Press %s to toggle first person%s.", tostring(Config.ToggleKey),
    Config.IndoorsOnly and " (indoors only)" or "")
