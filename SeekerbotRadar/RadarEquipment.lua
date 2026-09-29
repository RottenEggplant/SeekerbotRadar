-- Appended to SurvivalPlayer.lua: saved per-player radar preference.

local radarPlayerCreate = SurvivalPlayer.server_onCreate
function SurvivalPlayer.server_onCreate(self)
    radarPlayerCreate(self)
    -- Unlock older saves too, while preserving their ON/OFF preference.
    local equipment = self.sv.saved.seekerbotRadar or {}
    equipment.unlocked = true
    equipment.enabled = equipment.enabled == true
    self.sv.saved.seekerbotRadar = equipment
    self.storage:save(self.sv.saved)
    self.network:setClientData(self.sv.saved)
end

local radarPlayerData = SurvivalPlayer.client_onClientDataUpdate
function SurvivalPlayer.client_onClientDataUpdate(self, data)
    radarPlayerData(self, data)
    self.player.clientPublicData = self.player.clientPublicData or {}
    self.player.clientPublicData.seekerbotRadar = data.seekerbotRadar or { unlocked = false, enabled = false }
end

function SurvivalPlayer.sv_e_setSeekerbotRadar(self, params, sender)
    if sender and sender.id ~= self.player.id then return end
    local equipment = self.sv.saved.seekerbotRadar
    if not equipment or not equipment.unlocked or type(params) ~= "table" or type(params.enabled) ~= "boolean" then return end
    equipment.enabled = params.enabled
    self.storage:save(self.sv.saved)
    self.network:setClientData(self.sv.saved)
end
