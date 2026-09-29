-- Appended to LogBook.lua. Add a radar switch in the existing book's footer.
local radarBookCreate = LogBook.client_onCreate
function LogBook.client_onCreate(self)
    radarBookCreate(self)
    if not self.tool:isLocal() then return end
    self.cl.radarKeyButton = {
        Name = "SeekerbotRadarKeyItem", Type = "Button", Skin = "GenericButton",
        FontName = "SM_HeaderSmall", TextAlign = "Center", TextColour = "1 1 1 1",
        Caption = "SEEKERBOT RADAR: LOADING", NeedMouse = true, NeedKey = false,
        onClick = "cl_radarToggle", x = 42, y = 550, width = 350, height = 28, Childs = {}
    }
    self.cl.mainPanel.Childs[#self.cl.mainPanel.Childs + 1] = self.cl.radarKeyButton
end

local radarBookUpdateGui = LogBook.cl_updateGui
function LogBook.cl_updateGui(self, force)
    radarBookUpdateGui(self, force)
    if not self.cl.radarKeyButton then return end
    local player = sm.localPlayer.getPlayer()
    local equipment = player and player.clientPublicData and player.clientPublicData.seekerbotRadar
    local caption = "SEEKERBOT RADAR: LOADING"

    if equipment and equipment.unlocked then
        caption = equipment.enabled and "SEEKERBOT RADAR: ON" or "SEEKERBOT RADAR: OFF"
    end
    if self.cl.radarKeyButton.Caption ~= caption then
        self.cl.radarKeyButton.Caption = caption
        self.cl.render = true
    end
end

function LogBook.cl_radarToggle(self)
    local player = sm.localPlayer.getPlayer()
    local equipment = player and player.clientPublicData and player.clientPublicData.seekerbotRadar
    if not equipment then
        sm.gui.chatMessage("Seekerbot Radar data unavailable.")
        return
    end

    self.network:sendToServer("sv_radarToggle", { enabled = not equipment.enabled })
end

function LogBook.sv_radarToggle(self, params, player)
    local owner = self.tool:getOwner()
    if not owner or not player or owner.id ~= player.id or type(params) ~= "table" or type(params.enabled) ~= "boolean" then return end
    sm.event.sendToPlayer(player, "sv_e_setSeekerbotRadar", { enabled = params.enabled })
end
