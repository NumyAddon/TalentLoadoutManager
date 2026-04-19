if not C_ClassTalents.SwitchToLoadoutByIndex then return end -- @todo delete the check in 12.0.5, and delete the old file

local addonName, ns = ...;

--- @class TalentLoadoutManager
local TLM = ns.TLM;

--- @class TLM_BlizzardLoadoutChangerV2: AceModule, NumyAceEvent-3.0
local Module = TLM:NewModule("BlizzardLoadoutChanger", "NumyAceEvent-3.0");
TLM.BlizzardLoadoutChanger = Module;

function Module:TRAIT_CONFIG_UPDATED(_, configID)
    if not self.updatePending or configID ~= C_ClassTalents.GetActiveConfigID() then return; end
    RunNextFrame(function()
        self.updatePending = false;
        self.pendingConfigID = nil;

        if self.onAfterChangeCallback then
            local onAfterChangeCallback = self.onAfterChangeCallback;
            RunNextFrame(function() securecall(onAfterChangeCallback); end);
            self.onAfterChangeCallback = nil;
        end
    end);
    self:UnregisterAllEvents();
end

function Module:CONFIG_COMMIT_FAILED()
    self.updatePending = false;
    self.pendingConfigID = nil;
    self:UnregisterAllEvents();
end

function Module:GetLoadoutIndexByConfigID(configID)
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID()
    for index, id in ipairs(configIDs) do
        if id == configID then
            return index;
        end
    end

    return nil;
end

function Module:SelectLoadout(configID, autoApply, onAfterChangeCallback)
    self.updatePending = false;
    self.pendingConfigID = nil;
    self.onAfterChangeCallback = nil;

    if not autoApply then
        C_ClassTalents.LoadConfig(configID, false);

        return;
    end

    C_ClassTalents.SwitchToLoadoutByIndex(self:GetLoadoutIndexByConfigID(configID));
    self:RegisterEvent('TRAIT_CONFIG_UPDATED');
    self:RegisterEvent('CONFIG_COMMIT_FAILED');
    self.updatePending = true;
    self.pendingConfigID = configID;
    self.onAfterChangeCallback = onAfterChangeCallback;
end
