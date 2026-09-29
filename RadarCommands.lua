-- Appended to SurvivalGame.lua. Commands must be registered by the game script.
local radarOriginalBind = SurvivalGame.bindChatCommands
function SurvivalGame.bindChatCommands(self)
    radarOriginalBind(self)
    if sm.isHost then
        sm.game.bindChatCommand("/radar", { { "string", "action", true } }, "cl_onChatCommand", "Use /radar next to relocate the Seekerbot")
    end
end

local radarOriginalChat = SurvivalGame.cl_onChatCommand
function SurvivalGame.cl_onChatCommand(self, params)
    if params[1] ~= "/radar" then return radarOriginalChat(self, params) end
    if params[2] ~= "next" then
        sm.gui.chatMessage("Usage: /radar next")
        return
    end
    self.network:sendToServer("sv_radarNext", {})
end

function SurvivalGame.sv_radarNext(self, params, player)
    local host = sm.player.getHostPlayer()
    if not player or not host or player.id ~= host.id then return end
    if not sm.exists(self.sv.scannerbotManager) then
        self.network:sendToClient(player, "client_showMessage", "Seekerbot manager is not ready.")
        return
    end
    sm.event.sendToScriptableObject(self.sv.scannerbotManager, "sv_radarNext", { player = player })
end
