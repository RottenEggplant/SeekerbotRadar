-- Seekerbot Radar: appended to ScannerbotManager.lua by Install.ps1.
-- These wrappers preserve the game's callbacks and add only client-side UI.
-- Debug command: ask the real server manager to start its normal relocation.

-- Welcome to the Seekerbot Radar Mod, by Rotten Eggplant.
-- This mod displays the Seekerbot's current location and distance from the player
-- on the compass HUD; it displays a current status HUD in the upper right of the 
-- screen; it plays a ping when it starts or ends Seeking; a warning appears when it 
-- starts Seeking; and finally, you can tell the Seekerbot to fuck off with a command.

-- The "fuck off" command (/radar next)

function ScannerbotManager.sv_radarNext(self, params)
    local player = params.player
    local host = sm.player.getHostPlayer()
    if not player or not host or player.id ~= host.id then return end
    local function reply(message)
        self.network:sendToClient(player, "cl_radarReply", message)
    end
    local data = self.sv.saved.scannerbotData
    if not data or not self.sv.loadedRoads then
        reply("Seekerbot is inactive or its road data is not ready.")
        return
    end
    if data.behaviour ~= ScannerbotBehaviour.ROAD then
        reply("Seekerbot is already relocating. Wait until it is SEEKING.")
        return
    end
    self:sv_changeLocation()
    if self.sv.saved.scannerbotData.behaviour == ScannerbotBehaviour.RELOCATE_ASCEND then
        self.sv.requestRelocateTick = nil
        self:sv_saveAndSync()
        reply("Seekerbot chose its next location and is ASCENDING.")
    else
        reply("Seekerbot could not find a relocation destination.")
    end
end

-- This just tells the chatbox to display the above messages
function ScannerbotManager.cl_radarReply(self, message)
    sm.gui.chatMessage(message)
end

local RadarIcon = "SeekerbotRadar_Compass" -- Name of the compass icon
local RadarTexture = "$SURVIVAL_DATA/Gui/SeekerbotRadar/status-neutral.png" -- The white template for the icons

-- World distances are meters (even though it says "mi", "yards" and "feet"). Change these two values to tune the warning bands.
local NearDistance = 1500 * 0.3048 -- < 500 yards away
local CautionDistance = 1609.344 -- < 1 mile away
local DistanceColours = {
    near = sm.color.new("ff3030ff"), -- Red
    caution = sm.color.new("ffdf00ff"), -- Yellow
    far = sm.color.new("40ff40ff") -- Green
}

-- These are for the icon in the upper right corner
local StatusTexture = "status-neutral.png"
local ActiveColour = "0.25 1 0.25 1"
local InactiveColour = "0.55 0.55 0.55 1"

-- These are for the warning that pops up when the Seekerbot begins seeking.
local WarningDuration = 2.0
local WarningPeakAlpha = 0.65
local StartupAlertDelay = 10.0 -- Seconds after the local character first becomes available.
local function radarEquipmentEnabled(player)
    local equipment = player and player.clientPublicData and player.clientPublicData.seekerbotRadar
    return equipment ~= nil and equipment.unlocked == true and equipment.enabled == true
end

-- This function controls the warning label that pops up.
local function updateWarning(radar, character, dt)
    if not sm.exists(character) then return end
    if radar.startupAlertPending and radar.characterElapsed >= StartupAlertDelay then
        radar.startupAlertPending = nil
        if radar.previousBehaviour == ScannerbotBehaviour.ROAD then
            radar.pendingPing = true
            radar.pendingWarning = true
        end
    end
    if radar.pendingPing then
        sm.effect.playEffect("Scannerbot - Ping", character.worldPosition)
        radar.pendingPing = nil
    end
    if radar.pendingWarning then
        radar.warningElapsed = 0
        radar.pendingWarning = nil
        dt = 0 -- Start the pulse now; do not consume the delay frame's time.
    end
    if radar.warningElapsed == nil then return end
    radar.warningElapsed = radar.warningElapsed + dt
    if radar.warningElapsed >= WarningDuration then
        if radar.warningGui then radar.warningGui:close() end
        radar.warningGui = nil
        radar.warningElapsed = nil
        return
    end
    if not radar.warningGui then
        radar.warningGui = sm.jsonGui.createGui({ layer = "LuaHudShared", isHud = true, needsCursor = false, isInteractive = false })
    end
    -- One smooth pulse over WarningDuration, independent of the startup delay.
    radar.warningLayout.Alpha = WarningPeakAlpha * math.sin(math.pi * radar.warningElapsed / WarningDuration)
    radar.warningGui:render(radar.warningLayout)
end

-- These are the statuses that the Seekerbot can be in.
local StatusNames = {
    [ScannerbotBehaviour.ROAD] = "SEEKING",
    [ScannerbotBehaviour.RELOCATE_ASCEND] = "ASCENDING",
    [ScannerbotBehaviour.RELOCATE] = "RELOCATING",
    [ScannerbotBehaviour.RELOCATE_DESCEND] = "DESCENDING"
}

local function updateStatusIcon(radar, hasCharacter, active, behaviour)
    if not hasCharacter then
        if radar.statusGui then radar.statusGui:close() end
        radar.statusGui = nil
        radar.statusColour = nil
        return
    end
    if not radar.statusGui then
        radar.statusGui = sm.jsonGui.createGui({ layer = "LuaHudShared", isHud = true, needsCursor = false, isInteractive = false })
    end
    -- JsonGui coordinates use a 720-unit height, not physical display pixels.
    local displayWidth, displayHeight = sm.gui.getScreenSize()
    local hudWidth = displayWidth * 720 / math.max(displayHeight, 1)
    radar.statusLayout.x = math.max(0, hudWidth - radar.statusLayout.width - 24)
    radar.statusLabel.Caption = StatusNames[behaviour] or "INACTIVE"
    local colour = active and ActiveColour or InactiveColour
    if radar.statusColour ~= colour then
        -- Colour multiplies the texture's RGB channels. White can take any tint.
        radar.statusImage.Colour = colour
        radar.statusColour = colour
    end
    -- Match the stock Seekerbot HUD's per-frame render lifecycle, including loading.
    radar.statusGui:render(radar.statusLayout)
    if not radar.loggedPosition then
        local x, y = radar.statusGui:getWidgetAbsolutePosition("SeekerbotRadar_CornerIcon")
        sm.log.info("Seekerbot Radar corner icon (720-space):", x, y, "texture:", StatusTexture)
        radar.loggedPosition = true
    end
end

local function removeRadarIcon(self)
    local radar = self.cl and self.cl.seekerRadar
    if radar and radar.compass then
        if sm.exists(radar.compass) then
            radar.compass:compassRemoveIcon(RadarIcon)
        end
        radar.compass = nil
        radar.distanceBand = nil
    end
end

local function createRadarState()
    -- Each manager gets its own GUI table, so world reloads cannot share state.
    local statusImage = {
        Name = "SeekerbotRadar_CornerIcon", Type = "ImageBox", Skin = "ImageBox",
        ImageTexture = StatusTexture, Colour = InactiveColour,
        NeedMouse = false, NeedKey = false, Childs = {},
        x = 22, y = 0, width = 20, height = 20
    }
    local statusLabel = {
        Name = "SeekerbotRadar_Phase", Type = "TextBox", Skin = "TextBox",
        FontName = "SM_HeaderTiny", TextAlign = "Center", TextColour = "1 1 1 1",
        Caption = "INACTIVE", NeedMouse = false, NeedKey = false, Childs = {},
        x = 0, y = 23, width = 64, height = 12
    }
    -- Separate siblings keep the black image tint from affecting the white text.
    local statusPlate = {
        Name = "SeekerbotRadar_PhaseBackground", Type = "ImageBox", Skin = "ImageBox",
        ImageTexture = "white_gui.png", Colour = "0 0 0 1",
        NeedMouse = false, NeedKey = false, Childs = {},
        x = 0, y = 23, width = 64, height = 12
    }
    return {
        received = false,
        statusImage = statusImage,
        statusLabel = statusLabel,
        statusLayout = {
            Name = "SeekerbotRadar_CornerPanel", 
			Type = "Widget", 
			Skin = "PanelEmpty",
            Anchor = "Top Left", 
			Layer = "LuaHudShared", 
			Visible = true,
            NeedMouse = false, 
			NeedKey = false, 
			InheritsPick = true,
            LayoutRule = "Absolute",
            x = 24, y = 24, width = 64, height = 35, Childs = { statusImage, statusPlate, statusLabel }
        },
        warningLayout = {
            Name = "SeekerbotRadar_Warning", 
			Type = "Widget", 
			Skin = "PanelEmpty",
            Anchor = "Center", 
			Layer = "LuaHudShared", 
			Visible = true, 
			Alpha = 0,
            NeedMouse = false, 
			NeedKey = false, 
			InheritsPick = true,
            x = 0, y = 0, width = 320, height = 240,
            Childs = {
                { Name = "SeekerbotRadar_WarningIcon", 
				  Type = "ImageBox", 
				  Skin = "ImageBox",
                  ImageTexture = StatusTexture, 
				  Colour = "1 0 0 1", 
				  NeedMouse = false, 
				  NeedKey = false,
                  x = 40, y = 0, width = 240, height = 240, Childs = {} },
                { Name = "SeekerbotRadar_WarningText", 
				  Type = "ImageBox", 
				  Skin = "ImageBox",
                  ImageTexture = "warning-text.png",
                  Colour = "1 1 1 1",
				  NeedMouse = false, 
				  NeedKey = false,
                  x = 0, y = 95, width = 320, height = 50, Childs = {}
				}
            }
        }
    }
end

local originalCreate = ScannerbotManager.client_onCreate
function ScannerbotManager.client_onCreate(self)
    originalCreate(self)
    self.cl.seekerRadar = createRadarState()
end

local originalDataUpdate = ScannerbotManager.client_onClientDataUpdate
function ScannerbotManager.client_onClientDataUpdate(self, data, channel)
    originalDataUpdate(self, data, channel)
    if channel == 1 then
        local radar = self.cl.seekerRadar
        local previous = radar.previousBehaviour
        local current = data and data.behaviour or nil
        local initialSeeking = not radar.received and current == ScannerbotBehaviour.ROAD
        local enabled = radarEquipmentEnabled(sm.localPlayer.getPlayer())
        if initialSeeking and enabled then radar.startupAlertPending = true end
        -- Cancel a stale startup warning if it stops seeking during the delay.
        if current ~= ScannerbotBehaviour.ROAD then radar.startupAlertPending = nil end
        local seekingAlert = radar.received and current == ScannerbotBehaviour.ROAD and
            previous == ScannerbotBehaviour.RELOCATE_DESCEND
        local shouldPing = seekingAlert or (radar.received and previous == ScannerbotBehaviour.ROAD
            and current == ScannerbotBehaviour.RELOCATE_ASCEND)
        -- Remember every packet, including inactivity, so repeated packets stay silent.
        radar.previousBehaviour = current
        if shouldPing and enabled then radar.pendingPing = true end
        if seekingAlert and enabled then radar.pendingWarning = true end
        -- A received nil means inactive; no packet yet means unknown.
        self.cl.seekerRadar.received = true
    end
end

local originalUpdate = ScannerbotManager.client_onUpdate
function ScannerbotManager.client_onUpdate(self, dt)
    originalUpdate(self, dt)
    local radar = self.cl.seekerRadar
    local data = self.cl.scannerbotData
    local player = sm.localPlayer.getPlayer()
    local character = player and player.character
    if sm.exists(character) then radar.characterElapsed = (radar.characterElapsed or 0) + dt end
    local enabled = radarEquipmentEnabled(player)
    if not enabled then
        removeRadarIcon(self)
        updateStatusIcon(radar, false, false, nil)
        if radar.warningGui then radar.warningGui:close() end
        radar.warningGui = nil
        radar.warningElapsed = nil
        radar.pendingPing = nil
        radar.pendingWarning = nil
        radar.startupAlertPending = nil
        radar.equipmentEnabled = false
        return
    end
    if not radar.equipmentEnabled then
        radar.equipmentEnabled = true
        if radar.received and data and data.behaviour == ScannerbotBehaviour.ROAD then
            radar.startupAlertPending = true
        end
    end
    updateWarning(radar, character, dt)
    local overworld = WorldManager.Cl_GetWorld("overworld")
    local inOverworld = sm.exists(character) and sm.exists(overworld)
        and character:getWorld().id == overworld.id

    -- Separate HUD: remains visible even when the player disables the compass.
    -- ROAD is the road-scanning phase. All relocation phases stay gray.
    local scanning = radar.received and data ~= nil and data.behaviour == ScannerbotBehaviour.ROAD
    updateStatusIcon(radar, sm.exists(character), scanning, radar.received and data and data.behaviour or nil)

    local position
    if radar.received then
        if data then
            if sm.exists(data.scannerbotCharacter) then
                position = data.scannerbotCharacter.worldPosition
            else
                -- The server's last position remains usable outside render range.
                position = data.currentPosition
            end
        end
    end

    -- Respect the player's compass setting and avoid cross-world coordinates.
    local show = sm.game.getSettingBoolean("CompassHud") and sm.exists(character)
    local compass = g_compassHud
    if radar.compass ~= compass then removeRadarIcon(self) end
    if show and inOverworld and position and compass then
        if not radar.compass then
            -- true enables the native distance label. Sizes are GUI pixels.
            compass:compassAddIcon(RadarIcon, RadarTexture, true, 24, 24)
            compass:compassSetIconStacking(RadarIcon, false)
            radar.compass = compass
        end
        compass:compassSetIconWorldPosition(RadarIcon, position, overworld)
        -- Straight-line distance includes altitude, just like a world-space range.
        local playerPosition = character.worldPosition
        local dx, dy, dz = position.x - playerPosition.x, position.y - playerPosition.y, position.z - playerPosition.z
        local distanceSquared = dx * dx + dy * dy + dz * dz
        local band = distanceSquared < NearDistance * NearDistance and "near"
            or distanceSquared <= CautionDistance * CautionDistance and "caution" or "far"
        if radar.distanceBand ~= band then
            compass:setColor(RadarIcon, DistanceColours[band])
            radar.distanceBand = band
        end
        compass:setVisible(RadarIcon, true)
    else
        removeRadarIcon(self)
    end

end

local originalDestroy = ScannerbotManager.client_onDestroy
function ScannerbotManager.client_onDestroy(self)
    removeRadarIcon(self)
    local radar = self.cl and self.cl.seekerRadar
    if radar and radar.warningGui then
        radar.warningGui:close()
        radar.warningGui = nil
    end
    if radar and radar.statusGui then
        radar.statusGui:close()
        radar.statusGui = nil
    end
    if originalDestroy then originalDestroy(self) end
end
