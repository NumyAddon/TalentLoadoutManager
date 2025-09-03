local addonName, ns = ...;

--- @class TalentLoadoutManager
local TLM = ns.TLM;

--- @type TalentLoadoutManagerConfig
local Config = ns.Config;

--- @type TalentLoadoutManagerAPI
local API = TalentLoadoutManagerAPI;
local GlobalAPI = API.GlobalAPI;
local CharacterAPI = API.CharacterAPI;

--- @class TLMModule_Leveling: AceModule, AceHook-3.0, AceEvent-3.0, AceConsole-3.0
local Module = TLM:NewModule("Leveling", "AceHook-3.0", "AceEvent-3.0", "AceConsole-3.0");
TLM.LevelingModule = Module;

Module.CombatLockdownQueue = {};

function Module:OnInitialize()
    self.listener = CreateFrame("Frame");
    self.listener.Reset = function(listener)
        listener.PLAYER_LEVEL_UP = false;
        listener.TRAIT_TREE_CURRENCY_INFO_UPDATED = false;
        listener.elapsed = 0;
        listener:Hide();
    end
    self.listener:Reset();
    self.listener:SetScript("OnUpdate", function(listener, elapsed)
        listener.elapsed = listener.elapsed + elapsed;
        if listener.elapsed > 5 then
            listener:Reset();
            return;
        end
        if listener.PLAYER_LEVEL_UP and listener.TRAIT_TREE_CURRENCY_INFO_UPDATED then
            listener:Reset();
            if InCombatLockdown() then
                self:AddToCombatLockdownQueue(self.ReapplyLoadout, self);
                return;
            end
            RunNextFrame(function()
                self:ReapplyLoadout();
            end);
        end
    end);

end

function Module:OnEnable()
    self:RegisterEvent("PLAYER_LEVEL_UP", "OnEvent");
    self:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", "OnEvent");
end

function Module:OnDisable()
    self:UnregisterEvent("PLAYER_LEVEL_UP");
    self:UnregisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED");
    self.listener:Reset();
end

function Module:OnEvent(event, ...)
    if not Config:GetConfig("autoApplyOnLevelUp") then return; end
    if event == "PLAYER_LEVEL_UP" then
        local level = ...;
        if level < 10 then return; end
    elseif event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" then
        local treeID = ...;
        local specID = PlayerUtil.GetCurrentSpecID();
        if not specID then return; end
        local playerTreeID = C_ClassTalents.GetTraitTreeForSpec(specID);
        if treeID ~= playerTreeID then return; end
    end
    self.listener:Show();
    self.listener[event] = true;
end

function Module:ReapplyLoadout()
    local loadoutID = CharacterAPI:GetActiveLoadoutID();
    if not loadoutID then return end

    local loadoutInfo = GlobalAPI:GetLoadoutInfoByID(loadoutID);
    if not loadoutInfo then return end

    self:Print("Automatically re-applying loadout", loadoutInfo.displayName, ", go to /TLM to disable this behavior.");
    local mapBefore = self:GetSpellIDMap();
    CharacterAPI:LoadLoadout(loadoutID, true);
    local mapAfter = self:GetSpellIDMap();

    if mapBefore and mapAfter then
        for spellID, rankAfter in pairs(mapAfter) do
            if mapBefore[spellID] ~= rankAfter then
                if (mapBefore[spellID] or 0) == 0 then
                    self:Print("New Talent Learned:", C_Spell.GetSpellLink(spellID));
                else
                    self:Print("Talent Upgraded:", C_Spell.GetSpellLink(spellID), "to rank", rankAfter);
                end
            end
        end
    end
end

function Module:AddToCombatLockdownQueue(func, ...)
    if #self.CombatLockdownQueue == 0 then
        self:RegisterEvent("PLAYER_REGEN_ENABLED");
    end

    tinsert(self.CombatLockdownQueue, { func = func, args = { ... } });
end

function Module:PLAYER_REGEN_ENABLED()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED");
    if #self.CombatLockdownQueue == 0 then return; end

    for _, item in pairs(self.CombatLockdownQueue) do
        item.func(unpack(item.args));
    end
    wipe(self.CombatLockdownQueue);
end

function Module:GetSpellIDMap()
    local map = {}

    local configID = C_ClassTalents.GetActiveConfigID()
    if configID == nil then return end

    local configInfo = C_Traits.GetConfigInfo(configID)
    if configInfo == nil then return end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        for _, nodeID in ipairs(nodes) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
            if nodeInfo.activeEntry and nodeInfo.activeEntry.entryID and nodeInfo.activeEntry.rank > 0 then
                local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
                if entryInfo and entryInfo.definitionID then
                    local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                    if definitionInfo.spellID then
                        map[definitionInfo.spellID] = nodeInfo.activeEntry.rank
                    end
                end
            end
        end
    end

    return map
end
