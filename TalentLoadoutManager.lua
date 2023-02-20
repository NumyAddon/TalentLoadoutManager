local addonName, ns = ...;

--- @class TalentLoadoutManager
local TLM = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0");
ns.TLM = TLM;

local SERIALIZATION_NODE_SEPARATOR = "\n";
--- format: nodeID_entryID_spellID_rank
local SERIALIZATION_VALUE_SEPARATOR = "_";

--@debug@
_G.TalentLoadoutManager = TLM;
if not _G.TLM then _G.TLM = TLM; end
--@end-debug@


TLM.Event = {
    --- payload: classID, specID, loadoutID, loadoutInfo
    CustomLoadoutApplied = "CustomLoadoutApplied",
    --- payload: classID, specID, loadoutID, loadoutInfo
    --LoadoutCreated = "LoadoutCreated", -- todo?
    --- payload: classID, specID, loadoutID
    --LoadoutDeleted = "LoadoutDeleted", -- todo?
    --- payload: classID, specID, loadoutID, loadoutInfo - loadoutID is either configID or customLoadoutID
    LoadoutUpdated = "LoadoutUpdated",
    --- payload: <none>
    LoadoutListUpdated = "LoadoutListUpdated",
};

--- @alias TalentLoadoutManager_LoadoutDisplayInfo
--- @field id number|string  - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts
--- @field displayName string
--- @field loadoutInfo TalentLoadoutManager_LoadoutInfo
--- @field owner string|nil
--- @field playerIsOwner boolean
--- @field isBlizzardLoadout boolean
--- @field classID number
--- @field specID number

--- @alias TalentLoadoutManager_LoadoutInfo
--- @field name string
--- @field selectedNodes string - serialized loadout
--- @field id number|string - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts

--- @alias TalentLoadoutManager_DeserializedLoadout
--- @field nodeID number
--- @field entryID number
--- @field spellID number
--- @field rank number


local LOADOUT_SERIALIZATION_VERSION = 1;
function TLM:OnInitialize()
    LOADOUT_SERIALIZATION_VERSION = C_Traits.GetLoadoutSerializationVersion and C_Traits.GetLoadoutSerializationVersion() or LOADOUT_SERIALIZATION_VERSION;
    Mixin(self, CallbackRegistryMixin);
    CallbackRegistryMixin.OnLoad(self);

    TalentLoadoutManagerDB = TalentLoadoutManagerDB or {};
    TalentLoadoutManagerCharDB = TalentLoadoutManagerCharDB or {};
    self.db = TalentLoadoutManagerDB;
    self.charDb = TalentLoadoutManagerCharDB;
    self.deserializationCache = {};

    local defaults = {
        blizzardLoadouts = {},
        customLoadouts = {},
        customLoadoutAutoIncrement = 1,
        config = {},
    };
    local defaultConfig = {
        autoScale = true,
        autoPosition = true,
        autoApply = true,
        integrateWithSimc = true,
    };

    for key, value in pairs(defaults) do
        if self.db[key] == nil then
            self.db[key] = value;
        end
    end
    for key, value in pairs(defaultConfig) do
        if self.db.config[key] == nil then
            self.db.config[key] = value;
        end
    end

    ns.Config:Initialize();
    self:RegisterChatCommand('tlm', function() ns.Config:OpenConfig() end)
    self:RegisterChatCommand('talentloadoutmanager', function() ns.Config:OpenConfig() end)

    self.charDb.customLoadoutConfigID = self.charDb.customLoadoutConfigID or {};
    self.charDb.selectedCustomLoadoutID = self.charDb.selectedCustomLoadoutID or {};
    self.loadoutByIDCache = {};

    self:RegisterEvent("SPELLS_CHANGED");
end

function TLM:SPELLS_CHANGED()
    self:UnregisterEvent("SPELLS_CHANGED");
    local playerName, playerRealm = UnitFullName("player")
    self.playerName = playerName .. "-" .. playerRealm;
    self.playerClassID = PlayerUtil.GetClassID();
    self.playerSpecID = PlayerUtil.GetCurrentSpecID();
    self:RebuildLoadoutByIDCache();
    self:UpdateBlizzardLoadouts();

    self:RegisterEvent("TRAIT_CONFIG_UPDATED");
    self:RegisterEvent("TRAIT_CONFIG_DELETED");
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
end

function TLM:TRAIT_CONFIG_UPDATED()
    RunNextFrame(function()
        self:UpdateBlizzardLoadouts();
    end);
end

function TLM:TRAIT_CONFIG_CREATED(_, configInfo)
    if configInfo.type ~= Enum.TraitConfigType.Combat then return; end
    self:UnregisterEvent("TRAIT_CONFIG_CREATED");
    local specID = self.playerSpecID;
    self.charDb.customLoadoutConfigID[specID] = configInfo.ID;
    local loadout = self.deferredLoadout;
    self.deferredLoadout = nil;
    RunNextFrame(function()
        -- delayed to ensure processing happens after the talent UI is done
        self:ApplyCustomLoadout(loadout);
    end)
end

function TLM:TRAIT_CONFIG_DELETED(_, configID)
    local classID = self.playerClassID;
    local specID = self.playerSpecID;
    if
        self.db.blizzardLoadouts[classID]
        and self.db.blizzardLoadouts[classID][specID]
        and self.db.blizzardLoadouts[classID][specID][self.playerName]
        and self.db.blizzardLoadouts[classID][specID][self.playerName][configID]
    then
        self.db.blizzardLoadouts[classID][specID][self.playerName][configID] = nil;
        self:TriggerEvent(self.Event.LoadoutListUpdated);
    end

    if self.charDb.customLoadoutConfigID[specID] == configID then
        self.charDb.customLoadoutConfigID[specID] = nil;
    end

    self.loadoutByIDCache[configID] = nil;
end

function TLM:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self.playerSpecID = PlayerUtil.GetCurrentSpecID();
    self.spellNodeMap = nil;
end

function TLM:RebuildLoadoutByIDCache()
    self.loadoutByIDCache = {};
    for classID, specList in pairs(self.db.blizzardLoadouts) do
        for specID, playerList in pairs(specList) do
            for playerName, loadoutList in pairs(playerList) do
                for configID, loadoutInfo in pairs(loadoutList) do
                    local displayName = CreateAtlasMarkup("gmchat-icon-blizz", 16, 16) .. loadoutInfo.name;
                    if playerName ~= self.playerName then
                        displayName = displayName .. " (" .. playerName .. ")";
                    end
                    local displayInfo = {
                        id = configID,
                        displayName = displayName,
                        loadoutInfo = loadoutInfo,
                        owner = playerName,
                        playerIsOwner = playerName == self.playerName,
                        isBlizzardLoadout = true,
                        classID = classID,
                        specID = specID,
                    };
                    self.loadoutByIDCache[configID] = displayInfo;
                end
            end
        end
    end

    for classID, specList in pairs(self.db.customLoadouts) do
        for specID, loadoutList in pairs(specList) do
            for loadoutID, loadoutInfo in pairs(loadoutList) do
                local displayInfo = {
                    id = loadoutID,
                    displayName = loadoutInfo.name,
                    loadoutInfo = loadoutInfo,
                    owner = nil,
                    playerIsOwner = true,
                    isBlizzardLoadout = false,
                    classID = classID,
                    specID = specID,
                };
                self.loadoutByIDCache[loadoutID] = displayInfo;
            end
        end
    end
end

function TLM:GetActiveBlizzardLoadoutConfigID()
    if not self.playerSpecID then return nil; end

    local lastSelected = C_ClassTalents.GetLastSelectedSavedConfigID(self.playerSpecID);
    local selectionID = ClassTalentFrame
        and ClassTalentFrame.TalentsTab
        and ClassTalentFrame.TalentsTab.LoadoutDropDown
        and ClassTalentFrame.TalentsTab.LoadoutDropDown.GetSelectionID
        and ClassTalentFrame.TalentsTab.LoadoutDropDown:GetSelectionID();

    return selectionID or lastSelected or C_ClassTalents.GetActiveConfigID() or nil;
end

function TLM:GetTreeID()
    local configInfo = C_Traits.GetConfigInfo(C_ClassTalents.GetActiveConfigID());

    return configInfo and configInfo.treeIDs and configInfo.treeIDs[1];
end

--- @param spellID number
--- @return (nil|number, nil|number) nodeID, entryID - nil if not found or error
function TLM:GetNodeAndEntryBySpellID(spellID)
    if not self.spellNodeMap then
        local configID = C_ClassTalents.GetActiveConfigID();
        if configID == nil then return; end

        self.spellNodeMap = {};

        local treeID  = self:GetTreeID();
        local nodes = C_Traits.GetTreeNodes(treeID);
        for _, nodeID in pairs(nodes) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
            for _, entryID in pairs(nodeInfo.entryIDs) do
                local entryInfo = C_Traits.GetEntryInfo(configID, entryID);
                if entryInfo and entryInfo.definitionID then
                    local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID);
                    if definitionInfo.spellID then
                        self.spellNodeMap[definitionInfo.spellID] = {
                            nodeID = nodeID,
                            entryID = entryID,
                        };
                    end
                end
            end
        end
    end

    local result = self.spellNodeMap[spellID];
    if result then
        return result.nodeID, result.entryID;
    end
end

--- @param nodeID number
--- @return boolean
function TLM:IsChoiceNode(nodeID)
    local configID = C_ClassTalents.GetActiveConfigID();
    if configID == nil then return; end

    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
    if nodeInfo and nodeInfo.entryIDs then
        return #nodeInfo.entryIDs > 1;
    end
    return false;
end

--- @return number incremented unique ID
function TLM:IncrementCustomLoadoutAutoIncrement()
    self.db.customLoadoutAutoIncrement = self.db.customLoadoutAutoIncrement + 1;

    return self.db.customLoadoutAutoIncrement;
end

function TLM:UpdateBlizzardLoadouts()
    local classID = self.playerClassID;
    local specID = self.playerSpecID;
    self.db.blizzardLoadouts[classID] = self.db.blizzardLoadouts[classID] or {};
    self.db.blizzardLoadouts[classID][specID] = self.db.blizzardLoadouts[classID][specID] or {};
    if self.db.blizzardLoadouts[classID][specID][self.playerName] then
        for configID, _ in pairs(self.db.blizzardLoadouts[classID][specID][self.playerName]) do
            self.loadoutByIDCache[configID] = nil;
        end
    end
    self.db.blizzardLoadouts[classID][specID][self.playerName] = {};

    local activeConfigID = C_ClassTalents.GetActiveConfigID();
    for _, configID in pairs(C_ClassTalents.GetConfigIDsBySpecID()) do
        if configID ~= activeConfigID and configID ~= self.charDb.customLoadoutConfigID then
            self:UpdateBlizzardLoadout(configID);
        end
    end
    self:TriggerEvent(self.Event.LoadoutListUpdated);
end

function TLM:UpdateBlizzardLoadout(configID)
    local classID = self.playerClassID;
    local specID = self.playerSpecID;
    self.db.blizzardLoadouts[classID] = self.db.blizzardLoadouts[classID] or {};
    self.db.blizzardLoadouts[classID][specID] = self.db.blizzardLoadouts[classID][specID] or {};
    self.db.blizzardLoadouts[classID][specID][self.playerName] = self.db.blizzardLoadouts[classID][specID][self.playerName] or {};

    local configInfo = C_Traits.GetConfigInfo(configID);
    if not configInfo or configInfo.type ~= Enum.TraitConfigType.Combat then return; end

    local serialized = self:SerializeLoadout(configID);
    if serialized then
        local loadoutInfo = {
            selectedNodes = serialized,
            name = configInfo.name,
            id = configID,
        };
        self.db.blizzardLoadouts[classID][specID][self.playerName][configID] = loadoutInfo;
        local displayName = CreateAtlasMarkup("gmchat-icon-blizz", 16, 16) .. loadoutInfo.name;
        local displayInfo = {
            id = configID,
            displayName = displayName,
            loadoutInfo = loadoutInfo,
            owner = self.playerName,
            playerIsOwner = true,
            isBlizzardLoadout = true,
            classID = classID,
            specID = specID,
        };
        self.loadoutByIDCache[configID] = displayInfo;
        self:TriggerEvent(self.Event.LoadoutUpdated, classID, specID, configID, displayInfo);
    else
        self:Print("Failed to serialize loadout " .. configID);
    end
end

function TLM:UpdateCustomLoadout(customLoadoutID, selectedNodes, classIDOrNil, specIDOrNil)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;
    local loadoutInfo = self.db.customLoadouts[classID]
        and self.db.customLoadouts[classID][specID]
        and self.db.customLoadouts[classID][specID][customLoadoutID];

    if loadoutInfo then
        loadoutInfo.selectedNodes = selectedNodes;
        local displayInfo = {
            id = customLoadoutID,
            displayName = loadoutInfo.name,
            loadoutInfo = loadoutInfo,
            owner = nil,
            playerIsOwner = true,
            isBlizzardLoadout = false,
            classID = classID,
            specID = specID,
        }
        self.loadoutByIDCache[customLoadoutID] = displayInfo;
        self:TriggerEvent(self.Event.LoadoutUpdated, classID, specID, customLoadoutID, displayInfo);
    end
end

--- @param configID number
--- @return string serialized loadout
function TLM:SerializeLoadout(configID)
    local serialized = "";
    --- format: nodeID_entryID_spellID_rank
    local vSep = SERIALIZATION_VALUE_SEPARATOR;
    local nSep = SERIALIZATION_NODE_SEPARATOR;
    local formatString = "%d" .. vSep .. "%d" .. vSep .. "%d" .. vSep .. "%d" .. nSep;

    local treeID = self:GetTreeID();
    local nodes = C_Traits.GetTreeNodes(treeID);
    for _, nodeID in pairs(nodes) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
        local entryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID;
        if entryID and nodeInfo.ranksPurchased > 0 then
            local entryInfo = C_Traits.GetEntryInfo(configID, entryID);
            if entryInfo and entryInfo.definitionID then
                local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID);
                if definitionInfo.spellID then
                    serialized = serialized .. string.format(
                        formatString,
                        nodeID,
                        entryID,
                        definitionInfo.spellID,
                        nodeInfo.ranksPurchased
                    );
                end
            end
        end
    end

    return serialized;
end

--- @param serialized string
--- @return TalentLoadoutManager_DeserializedLoadout
function TLM:DeserializeLoadout(serialized)
    if not self.deserializationCache[serialized] then
        local loadout = {};
        local vSep = SERIALIZATION_VALUE_SEPARATOR;
        local nSep = SERIALIZATION_NODE_SEPARATOR;

        for node in string.gmatch(serialized, "([^" .. nSep .. "]+)") do
            local nodeID, entryID, spellID, rank = string.split(vSep, node);
            loadout[tonumber(nodeID)] = {
                nodeID = tonumber(nodeID),
                entryID = tonumber(entryID),
                spellID = tonumber(spellID),
                rank = tonumber(rank),
            };
        end

        self.deserializationCache[serialized] = loadout;
    end

    return CopyTable(self.deserializationCache[serialized]);
end

--- @return string|number|nil currently active (possibly custom) loadout ID, custom loadouts are prefixed with "C_"
function TLM:GetActiveLoadoutID()
    local activeLoadoutConfigID = self:GetActiveBlizzardLoadoutConfigID();
    local customLoadoutConfigID = self.charDb.customLoadoutConfigID[self.playerSpecID];
    local customLoadoutID = self.charDb.selectedCustomLoadoutID[self.playerSpecID];

    if activeLoadoutConfigID == customLoadoutConfigID and customLoadoutID then
        return customLoadoutID;
    end

    return activeLoadoutConfigID;
end

--- @param loadoutInfo TalentLoadoutManager_LoadoutInfo
--- @return (table, number) loadoutEntryInfo, foundIssues
function TLM:LoadoutInfoToEntryInfo(loadoutInfo)
    local configID = C_ClassTalents.GetActiveConfigID();
    local entryInfo = {};
    local foundIssues = 0;
    local deserialized = self:DeserializeLoadout(loadoutInfo.selectedNodes);

    for _, loadoutNodeInfo in pairs(deserialized) do
        local nodeInfoExists = false;
        local isChoiceNode = false;
        local nodeInfo = C_Traits.GetNodeInfo(configID, loadoutNodeInfo.nodeID);
        if nodeInfo then
            for _, entryID in pairs(nodeInfo.entryIDs) do
                if entryID == loadoutNodeInfo.entryID then
                    nodeInfoExists = true;
                    isChoiceNode = #nodeInfo.entryIDs > 1;
                end
            end
        end

        local nodeID, entryID = loadoutNodeInfo.nodeID, loadoutNodeInfo.entryID;
        if not nodeInfoExists then
            nodeID, entryID = self:GetNodeAndEntryBySpellID(loadoutNodeInfo.spellID);
            isChoiceNode = self:IsChoiceNode(nodeID);
        end
        if nodeID and entryID then
            table.insert(entryInfo, {
                selectionEntryID = isChoiceNode and entryID or nil,
                nodeID = nodeID,
                ranksPurchased = loadoutNodeInfo.rank,
            });
        else
            foundIssues = foundIssues + 1;
        end
    end

    return entryInfo, foundIssues;
end

--- @param configID number
--- @param loadoutEntryInfo table
--- @return number number of removed entries (due to successful purchases)
function TLM:PurchaseLoadoutEntryInfo(configID, loadoutEntryInfo)
    local removed = 0;
    for i, nodeEntry in pairs(loadoutEntryInfo) do
        local success = false;
        if nodeEntry.selectionEntryID then
            success = C_Traits.SetSelection(configID, nodeEntry.nodeID, nodeEntry.selectionEntryID);
        elseif nodeEntry.ranksPurchased then
            for rank = 1, nodeEntry.ranksPurchased do
                success = C_Traits.PurchaseRank(configID, nodeEntry.nodeID);
            end
        end
        if success then
            removed = removed + 1;
            loadoutEntryInfo[i] = nil;
        end
    end

    return removed;
end

--- @param loadoutID string|number
--- @return TalentLoadoutManager_LoadoutDisplayInfo|nil
function TLM:GetLoadoutByID(loadoutID)
    local displayInfo = self.loadoutByIDCache[loadoutID];
    if displayInfo then
        displayInfo = Mixin({}, displayInfo);
        displayInfo.isActive = self:GetActiveLoadoutID() == loadoutID;
    end

    return displayInfo;
end

--- @return TalentLoadoutManager_LoadoutDisplayInfo[] - list of all loadouts, isActive still refers to the current player only
function TLM:GetAllLoadouts()
    local loadouts = {};
    local activeLoadoutID = self:GetActiveLoadoutID();
    for loadoutID, displayInfo in pairs(self.loadoutByIDCache) do
        displayInfo = Mixin({}, displayInfo);
        displayInfo.isActive = activeLoadoutID == loadoutID;
        table.insert(loadouts, displayInfo);
    end

    return loadouts;
end

--- @return TalentLoadoutManager_LoadoutDisplayInfo[] - list of loadouts
function TLM:GetLoadouts(classIDOrNil, specIDOrNil)
    local loadouts = {}
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;

    if self.db.blizzardLoadouts[classID] and self.db.blizzardLoadouts[classID][specID] then
        for _, playerLoadouts in pairs(self.db.blizzardLoadouts[classID][specID]) do
            for loadoutID, _ in pairs(playerLoadouts) do
                table.insert(loadouts, self:GetLoadoutByID(loadoutID));
            end
        end
    end

    if self.db.customLoadouts[classID] and self.db.customLoadouts[classID][specID] then
        for loadoutID, _ in pairs(self.db.customLoadouts[classID][specID]) do
            table.insert(loadouts, self:GetLoadoutByID(loadoutID));
        end
    end

    return loadouts;
end

--- @param loadoutInfo TalentLoadoutManager_LoadoutInfo
function TLM:ApplyCustomLoadout(loadoutInfo, autoApply)
    --------------------------------------------------------------------------------------------
    ---
    --- plan A:
    --- note: this plan failed :( the game doesn't really support making changes to a loadout in the background, and then loading that
    --- 1. Reset tree of the targetConfigID
    --- 2.
    ---    if a configID other than targetConfigID is active:
    ---      - LoadConfigByPredicate to targetConfigID
    ---    else:
    ---      - C_ClassTalents.LoadConfig(targetConfigID, true)
    --- 3. Apply the custom loadout to activeConfigID (but don't commit)
    --- 4. Commit activeConfigID
    --- 5. After cast is done, C_ClassTalents.SaveConfig(targetConfigID)
    ---
    ---
    --- plan B:
    --- note: this plan is a bit shitty, but it seems to work.. for now..
    --- 1. switch to targetConfigID first
    --- 2. after switching, reset tree and apply custom loadout to activeConfigID
    --- 3. commit activeConfigID, but only if there are staging changes
    ---
    --------------------------------------------------------------------------------------------

    local specID = self.playerSpecID;
    local targetConfigID = self.charDb.customLoadoutConfigID[specID];
    local activeConfigID = C_ClassTalents.GetActiveConfigID();

    if targetConfigID == nil then
        if not C_ClassTalents.CanCreateNewConfig() then
            self:Print("You have too many blizzard loadouts. Please delete one in order to switch to a custom loadout.");
            return false;
        end
        if not C_ClassTalents.RequestNewConfig("TalentLoadoutManager") then
            self:Print("Failed to create new loadout.");
            return false;
        end

        --- deferred to TRAIT_CONFIG_CREATED
        self.deferredLoadout = loadoutInfo;
        self:RegisterEvent("TRAIT_CONFIG_CREATED");

        return true;
    end
    local loadoutEntryInfo, foundIssues = self:LoadoutInfoToEntryInfo(loadoutInfo);
    local entriesCount = #loadoutEntryInfo + foundIssues;

    if self:GetActiveBlizzardLoadoutConfigID() ~= targetConfigID then
        self:ApplyBlizzardLoadout(targetConfigID, true, function()
            RunNextFrame(function() self:ApplyCustomLoadout(loadoutInfo, autoApply); end);
        end);

        return true;
    end
    C_Traits.ResetTree(activeConfigID, self:GetTreeID());

    while(true) do
        local removed = self:PurchaseLoadoutEntryInfo(activeConfigID, loadoutEntryInfo);
        if(removed == 0) then
            break;
        end
        entriesCount = entriesCount - removed;
    end

    if entriesCount > 0 then
        self:Print("Failed to fully apply loadout. " .. entriesCount .. " entries could not be purchased.");
    end

    if autoApply and C_Traits.ConfigHasStagedChanges(activeConfigID) and not C_ClassTalents.CommitConfig(targetConfigID) then
        self:Print("Failed to commit loadout.");
        return false;
    end

    self.charDb.selectedCustomLoadoutID[self.playerSpecID] = loadoutInfo.id;
    local displayInfo = {
        id = loadoutInfo.id,
        displayName = loadoutInfo.name,
        loadoutInfo = loadoutInfo,
        owner = nil,
        playerIsOwner = true,
        isBlizzardLoadout = false,
        classID = self.playerClassID,
        specID = self.playerSpecID,
    }
    self:TriggerEvent(self.Event.CustomLoadoutApplied, self.playerClassID, specID, loadoutInfo.id, displayInfo);

    return true;
end

function TLM:ApplyCustomLoadoutByID(classIDOrNil, specIDOrNil, loadoutID)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;
    local loadoutInfo = self.db.customLoadouts[classID]
        and self.db.customLoadouts[classID][specID]
        and self.db.customLoadouts[classID][specID][loadoutID];

    if loadoutInfo then
        return self:ApplyCustomLoadout(loadoutInfo);
    end

    return false;
end

function TLM:ApplyBlizzardLoadout(configID, autoApply, onAfterChangeCallback)
    self.BlizzardLoadoutChanger:SelectLoadout(configID, autoApply, onAfterChangeCallback);
end

--- @param loadoutInfo TalentLoadoutManager_LoadoutInfo
function TLM:CreateCustomLoadoutFromLoadoutData(loadoutInfo, classIDOrNil, specIDOrNil)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;

    self.db.customLoadouts[classID] = self.db.customLoadouts[classID] or {};
    self.db.customLoadouts[classID][specID] = self.db.customLoadouts[classID][specID] or {};

    local id = "C_" .. self:IncrementCustomLoadoutAutoIncrement();
    local name = loadoutInfo.name or "Custom Loadout " .. id;
    local newLoadoutInfo = {
        id = id,
        name = name,
        selectedNodes = loadoutInfo.selectedNodes,
    }
    self.db.customLoadouts[classID][specID][id] = newLoadoutInfo;
    local displayInfo = {
        id = id,
        displayName = newLoadoutInfo.name,
        loadoutInfo = newLoadoutInfo,
        owner = nil,
        playerIsOwner = true,
        isBlizzardLoadout = false,
        classID = classID,
        specID = specID,
    }
    self.loadoutByIDCache[id] = displayInfo;
    self:TriggerEvent(self.Event.LoadoutUpdated, classID, specID, id, displayInfo);
    self:TriggerEvent(self.Event.LoadoutListUpdated);

    return newLoadoutInfo;
end

function TLM:CreateCustomLoadoutFromImportString(importString, autoApply, name, classIDOrNil, specIDOrNil)
    local selectedNodes, errorOrNil = self:BuildSerializedSelectedNodesFromImportString(importString, classIDOrNil, specIDOrNil);
    if selectedNodes then
        local loadoutInfo = {
            name = name,
            selectedNodes = selectedNodes,
        }
        loadoutInfo = self:CreateCustomLoadoutFromLoadoutData(loadoutInfo, classIDOrNil, specIDOrNil);
        self:ApplyCustomLoadout(loadoutInfo, autoApply);

        return loadoutInfo;
    end
    return false, errorOrNil;
end

function TLM:CreateCustomLoadoutFromActiveTalents(name, classIDOrNil, specIDOrNil)
    local selectedNodes = self:SerializeLoadout(C_ClassTalents.GetActiveConfigID());
    local loadoutInfo = {
        name = name,
        selectedNodes = selectedNodes,
    }
    loadoutInfo = self:CreateCustomLoadoutFromLoadoutData(loadoutInfo, classIDOrNil, specIDOrNil);
    self:ApplyCustomLoadout(loadoutInfo);

    return loadoutInfo;
end

function TLM:RenameCustomLoadout(classIDOrNil, specIDOrNil, loadoutID, newName)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;
    assert(type(loadoutID) == "string" or type(loadoutID) == "number", "loadoutID must be a string or number");

    if self.db.customLoadouts[classID] and self.db.customLoadouts[classID][specID] and self.db.customLoadouts[classID][specID][loadoutID] then
        local loadoutInfo = self.db.customLoadouts[classID][specID][loadoutID];
        loadoutInfo.name = newName;

        local displayInfo = {
            id = loadoutID,
            displayName = loadoutInfo.name,
            loadoutInfo = loadoutInfo,
            owner = nil,
            playerIsOwner = true,
            isBlizzardLoadout = false,
            classID = classID,
            specID = specID,
        }
        self.loadoutByIDCache[loadoutID] = displayInfo;
        self:TriggerEvent(self.Event.LoadoutUpdated, classID, specID, loadoutID, displayInfo);
        self:TriggerEvent(self.Event.LoadoutListUpdated);

        return true;
    end

    return false;
end

function TLM:RenameBlizzardLoadout(configID, newName)
    if not C_ClassTalents.RenameConfig(configID, newName) then
        return false;
    end

    self:UpdateBlizzardLoadout(configID);
    self:TriggerEvent(self.Event.LoadoutListUpdated);

    return true;
end

function TLM:DeleteCustomLoadout(classIDOrNil, specIDOrNil, loadoutID)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;
    assert(type(loadoutID) == "string" or type(loadoutID) == "number", "loadoutID must be a string or number");

    if self.db.customLoadouts[classID] and self.db.customLoadouts[classID][specID] and self.db.customLoadouts[classID][specID][loadoutID] then
        self.db.customLoadouts[classID][specID][loadoutID] = nil;
        self.loadoutByIDCache[loadoutID] = nil;

        --self:TriggerEvent(self.Event.LoadoutDeleted, classID, specID, loadoutID);
        self:TriggerEvent(self.Event.LoadoutListUpdated);

        return true;
    end

    return false;
end

function TLM:DeleteBlizzardLoadout(configID)
    local classID = self.playerClassID;
    local specID = self.playerSpecID;

    if not C_ClassTalents.DeleteConfig(configID) then
        return false;
    end

    self.loadoutByIDCache[configID] = nil;
    if
        self.db.blizzardLoadouts[classID]
        and self.db.blizzardLoadouts[classID][specID]
        and self.db.blizzardLoadouts[classID][specID][self.playerName]
        and self.db.blizzardLoadouts[classID][specID][self.playerName][configID]
    then
        self.db.blizzardLoadouts[classID][specID][self.playerName][configID] = nil;

        self:TriggerEvent(self.Event.LoadoutListUpdated);
    end

    return true;
end

function TLM:ExportLoadoutToString(classIDOrNil, specIDOrNil, loadoutInfo)
    local LOADOUT_SERIALIZATION_VERSION = 1;

    local deserialized = self:DeserializeLoadout(loadoutInfo.selectedNodes);
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;

    if specID ~= self.playerSpecID then
        self:Print("Exporting loadouts from other specs is not yet supported.");

        return false;
    end

    if not ClassTalentFrame then
        ClassTalentFrame_LoadUI();
    end
    local talentsTab = ClassTalentFrame.TalentsTab;
    local exportStream = ExportUtil.MakeExportDataStream();
    local treeID = self:GetTreeID();

    -- write header
    exportStream:AddValue(talentsTab.bitWidthHeaderVersion, LOADOUT_SERIALIZATION_VERSION);
    exportStream:AddValue(talentsTab.bitWidthSpecID, specID);
    -- treeHash is a 128bit hash, passed as an array of 16, 8-bit values
    -- empty tree hash will disable validation on import
    exportStream:AddValue(8 * 16, 0);

    self:WriteLoadoutContent(exportStream, deserialized, treeID, talentsTab);

    return exportStream:GetExportString();
end

function TLM:WriteLoadoutContent(exportStream, deserialized, treeID, talentsTab)
    local configID = C_ClassTalents.GetActiveConfigID();
    local treeNodes = C_Traits.GetTreeNodes(treeID);

    local deserializedByNodeID = {};
    for _, info in pairs(deserialized) do
        local nodeID, _ = self:GetNodeAndEntryBySpellID(info.spellID);
        deserializedByNodeID[nodeID] = info;
    end

    for _, nodeID in pairs(treeNodes) do
        local info = deserializedByNodeID[nodeID];
        exportStream:AddValue(1, info and 1 or 0);
        if info then
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
            local isPartiallyRanked = nodeInfo and nodeInfo.maxRanks ~= info.rank
            exportStream:AddValue(1, isPartiallyRanked and 1 or 0);
            if isPartiallyRanked then
                exportStream:AddValue(talentsTab.bitWidthRanksPurchased, info.rank);
            end

            local isChoiceNode = nodeInfo and nodeInfo.type == Enum.TraitNodeType.Selection;
            exportStream:AddValue(1, isChoiceNode and 1 or 0);
            if isChoiceNode then
                local entryIndex = 0;
                for i, entry in ipairs(nodeInfo and nodeInfo.entryIDs or {}) do
                    if entry == info.entryID then
                        entryIndex = i;
                        break;
                    end
                end

                exportStream:AddValue(2, entryIndex - 1);
            end
        end
    end
end

function TLM:BuildSerializedSelectedNodesFromImportString(importText, classIDOrNil, specIDOrNil)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;

    if specID ~= self.playerSpecID then
        -- note to self: this will require LibTalentTree to be able to handle other specs/classes

        return false, "Importing loadouts from other specs is not yet supported.";
    end

    local ImportExportMixin = ClassTalentImportExportMixin;

    local importStream = ExportUtil.MakeImportDataStream(importText);

    local headerValid, serializationVersion, specIDFromString, treeHash = ImportExportMixin:ReadLoadoutHeader(importStream);

    if(not headerValid) then
        return false, LOADOUT_ERROR_BAD_STRING;
    end

    if(serializationVersion ~= LOADOUT_SERIALIZATION_VERSION) then
        return false, LOADOUT_ERROR_SERIALIZATION_VERSION_MISMATCH;
    end

    if(specIDFromString ~= specID) then
        return false, LOADOUT_ERROR_WRONG_SPEC;
    end

    local treeID = self:GetTreeID();
    if not ImportExportMixin:IsHashEmpty(treeHash) then
        -- allow third-party sites to generate loadout strings with an empty tree hash, which bypasses hash validation
        if not ImportExportMixin:HashEquals(treeHash, C_Traits.GetTreeHash(treeID)) then
            return false, LOADOUT_ERROR_TREE_CHANGED;
        end
    end

    local loadoutContent = ImportExportMixin:ReadLoadoutContent(importStream, treeID);

    local configID = C_ClassTalents.GetActiveConfigID();
    local serialized = "";
    --- format: nodeID_entryID_spellID_rank
    local vSep = SERIALIZATION_VALUE_SEPARATOR;
    local nSep = SERIALIZATION_NODE_SEPARATOR;
    local formatString = "%d" .. vSep .. "%d" .. vSep .. "%d" .. vSep .. "%d" .. nSep;

    local nodes = C_Traits.GetTreeNodes(treeID);
    for i, nodeID in pairs(nodes) do
        local indexInfo = loadoutContent[i];
        if indexInfo.isNodeSelected then
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
            local entryID = indexInfo.isChoiceNode and nodeInfo.entryIDs[indexInfo.choiceNodeSelection] or nodeInfo.entryIDs[1];
            local entryInfo = C_Traits.GetEntryInfo(configID, entryID);
            if entryInfo and entryInfo.definitionID then
                local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID);
                if definitionInfo.spellID then
                    serialized = serialized .. string.format(
                        formatString,
                        nodeID,
                        entryID,
                        definitionInfo.spellID,
                        indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or nodeInfo.maxRanks
                    );
                end
            end
        end
    end

    return serialized;
end
