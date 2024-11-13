local addonName, ns = ...;

--- @class TalentLoadoutManager: AceAddon, AceConsole-3.0, AceEvent-3.0, AceHook-3.0, CallbackRegistryMixin
local TLM = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0");
ns.TLM = TLM;
TLM._ns = ns;

_G.TalentLoadoutManager = TLM;

ns.SERIALIZATION_NODE_SEPARATOR = "\n";
--- format: nodeID_entryID_spellIDOrSubTreeID_rank
ns.SERIALIZATION_VALUE_SEPARATOR = "_";
ns.MAX_LEVEL = 80;
local SERIALIZATION_NODE_SEPARATOR = ns.SERIALIZATION_NODE_SEPARATOR;
local SERIALIZATION_VALUE_SEPARATOR = ns.SERIALIZATION_VALUE_SEPARATOR;

--@debug@
if not _G.TLM then _G.TLM = TLM; end
--@end-debug@

--- @type TLM_ImportExportV1|TLM_ImportExportV2
local ImportExport = ns.ImportExport;

--- @type TLM_IcyVeinsImport
local IcyVeinsImport = ns.IcyVeinsImport;

local LibTT = LibStub("LibTalentTree-1.0");

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

do
    Mixin(TLM, CallbackRegistryMixin);
    CallbackRegistryMixin.OnLoad(TLM);
end

function TLM:OnInitialize()
    if NumyProfiler then
        --- @type NumyProfiler
        local NumyProfiler = NumyProfiler;
        NumyProfiler:WrapModules(addonName, 'Main', self);
        NumyProfiler:WrapModules(addonName, 'IcyVeinsImport', IcyVeinsImport);
        NumyProfiler:WrapModules(addonName, 'ImportExport', ImportExport);
        NumyProfiler:WrapModules(addonName, 'Config', ns.Config);
        NumyProfiler:WrapModules(addonName, 'API', TalentLoadoutManagerAPI);

        for moduleName, module in self:IterateModules() do
            NumyProfiler:WrapModules(addonName, moduleName, module);
        end
    end
    TalentLoadoutManagerDB = TalentLoadoutManagerDB or {};
    TalentLoadoutManagerCharDB = TalentLoadoutManagerCharDB or {};
    self.db = TalentLoadoutManagerDB;
    self.charDb = TalentLoadoutManagerCharDB;
    self.cache = {
        loadoutByID = {},
        exportStrings = {},
        deserializationCache = {},
        deserializationLevelingCache = {},
        treeNodes = {},
        orderedTreeNodes = {},
        spellNodeMap = {},
    };

    local defaults = {
        blizzardLoadouts = {},
        customLoadouts = {},
        customLoadoutAutoIncrement = 1,
        config = {},
    };

    for key, value in pairs(defaults) do
        if self.db[key] == nil then
            self.db[key] = value;
        end
    end

    ns.Config:Initialize();
    self:RegisterChatCommand('tlm', function() ns.Config:OpenConfig() end)
    self:RegisterChatCommand('talentloadoutmanager', function() ns.Config:OpenConfig() end)

    self.charDb.customLoadoutConfigID = self.charDb.customLoadoutConfigID or {};
    self.charDb.selectedCustomLoadoutID = self.charDb.selectedCustomLoadoutID or {};

    self:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED");
end

function TLM:TRAIT_CONFIG_LIST_UPDATED()
    self:UnregisterEvent("TRAIT_CONFIG_LIST_UPDATED");
    local playerName, playerRealm = UnitFullName("player")
    self.playerName = playerName .. "-" .. playerRealm;
    --- @type number
    self.playerClassID = PlayerUtil.GetClassID();
    --- @type number
    self.playerSpecID = PlayerUtil.GetCurrentSpecID(); ---@diagnostic disable-line: assign-type-mismatch
    self:RebuildLoadoutByIDCache();
    self:UpdateBlizzardLoadouts();
    self:DetectDeletedParents();

    self:RegisterEvent("TRAIT_CONFIG_UPDATED");
    self:RegisterEvent("TRAIT_CONFIG_DELETED");
    self:RegisterEvent("CONFIG_COMMIT_FAILED");
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
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

    self.cache.loadoutByID[configID] = nil;
    self:DetectDeletedParents();
end

function TLM:CONFIG_COMMIT_FAILED(_, configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return; end
    RunNextFrame(function()
        self:TriggerEvent(self.Event.LoadoutListUpdated);
    end);
end

function TLM:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self.playerSpecID = PlayerUtil.GetCurrentSpecID(); ---@diagnostic disable-line: assign-type-mismatch
    self:TriggerEvent(self.Event.LoadoutListUpdated);
end

function TLM:PLAYER_ENTERING_WORLD()
    -- forced respecs from LFG queues, do not trigger ACTIVE_PLAYER_SPECIALIZATION_CHANGED event
    if self.playerSpecID == PlayerUtil.GetCurrentSpecID() then return; end
    self.playerSpecID = PlayerUtil.GetCurrentSpecID(); ---@diagnostic disable-line: assign-type-mismatch
    self:TriggerEvent(self.Event.LoadoutListUpdated);
end

function TLM:GetParentMappingForLoadout(loadout, specID)
    if not loadout then return {}; end
    local mapping = Mixin({}, loadout.parentMapping or {});
    mapping[0] = mapping[self.playerName] or nil;
    if not mapping[0] and specID then
        mapping[0] = self.charDb.customLoadoutConfigID[specID] or nil;
    end

    return mapping;
end

function TLM:SetParentLoadout(childLoadoutID, parentLoadoutID)
    local displayInfo = self:GetLoadoutByID(childLoadoutID, true);
    if not displayInfo or not displayInfo.loadoutInfo then return; end

    local loadoutInfo = displayInfo.loadoutInfo;
    if not loadoutInfo then return end

    loadoutInfo.parentMapping = loadoutInfo.parentMapping or {};
    loadoutInfo.parentMapping[self.playerName] = parentLoadoutID;

    displayInfo.parentMapping = self:GetParentMappingForLoadout(loadoutInfo, displayInfo.specID);

    self:TriggerEvent(self.Event.LoadoutUpdated, displayInfo.classID, displayInfo.specID, displayInfo.id, displayInfo);
    self:TriggerEvent(self.Event.LoadoutListUpdated);
end

function TLM:DetectDeletedParents()
    local anyDeleted = false;
    local classID = self.playerClassID;
    for _, loadoutList in pairs(self.db.customLoadouts[classID] or {}) do
        for loadoutID, loadoutInfo in pairs(loadoutList) do
            local parentConfigID = loadoutInfo.parentMapping and loadoutInfo.parentMapping[self.playerName] or nil;
            if parentConfigID and not self.cache.loadoutByID[parentConfigID] then
                loadoutInfo.parentMapping[self.playerName] = nil;
                self.cache.loadoutByID[loadoutID].parentMapping = self:GetParentMappingForLoadout(loadoutInfo, loadoutInfo.specID);
                anyDeleted = true;
            end
        end
    end

    if anyDeleted then
        self:TriggerEvent(self.Event.LoadoutListUpdated);
    end
end

function TLM:RebuildLoadoutByIDCache()
    self.cache.loadoutByID = {};
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
                        parentMapping = nil,
                        classID = classID,
                        specID = specID,
                    };
                    self.cache.loadoutByID[configID] = displayInfo;
                end
            end
        end
    end

    for classID, specList in pairs(self.db.customLoadouts) do
        for specID, loadoutList in pairs(specList) do
            for loadoutID, loadoutInfo in pairs(loadoutList) do
                local namePrefix = loadoutInfo.levelingOrder and CreateAtlasMarkup("GarrMission_CurrencyIcon-Xp", 16, 16) or "";
                local displayInfo = {
                    id = loadoutID,
                    displayName = namePrefix .. loadoutInfo.name,
                    loadoutInfo = loadoutInfo,
                    owner = nil,
                    playerIsOwner = true,
                    isBlizzardLoadout = false,
                    parentMapping = self:GetParentMappingForLoadout(loadoutInfo, specID),
                    classID = classID,
                    specID = specID,
                };
                self.cache.loadoutByID[loadoutID] = displayInfo;
            end
        end
    end
end

function TLM:GetActiveBlizzardLoadoutConfigID()
    if not self.playerSpecID then return nil; end

    local lastSelected = C_ClassTalents.GetLastSelectedSavedConfigID(self.playerSpecID);
    local selectionID =
        (
            ClassTalentFrame
            and ClassTalentFrame.TalentsTab
            and ClassTalentFrame.TalentsTab.LoadoutDropDown
            and ClassTalentFrame.TalentsTab.LoadoutDropDown.GetSelectionID
            and ClassTalentFrame.TalentsTab.LoadoutDropDown:GetSelectionID()
        )
        or (
            PlayerSpellsFrame
            and PlayerSpellsFrame.TalentsFrame
            and PlayerSpellsFrame.TalentsFrame.LoadSystem
            and PlayerSpellsFrame.TalentsFrame.LoadSystem.GetSelectionID
            and PlayerSpellsFrame.TalentsFrame.LoadSystem:GetSelectionID()
        );

    return selectionID or lastSelected or C_ClassTalents.GetActiveConfigID() or nil;
end

function TLM:GetTreeID()
    local configInfo = C_Traits.GetConfigInfo(C_ClassTalents.GetActiveConfigID());

    return configInfo and configInfo.treeIDs and configInfo.treeIDs[1];
end

--- @param treeID number
--- @param orderByPosition boolean|nil - if true, the nodes are sorted by position, top to bottom, left to right
--- @return table<number, number> - [index] = nodeID
function TLM:GetTreeNodes(treeID, orderByPosition)
    if orderByPosition then
        if not self.cache.orderedTreeNodes[treeID] then
            local nodes = C_Traits.GetTreeNodes(treeID);
            table.sort(nodes, function(a, b)
                local aCol, aRow = LibTT:GetNodeGridPosition(a);
                local bCol, bRow = LibTT:GetNodeGridPosition(b);
                if not aCol or not aRow or not bCol or not bRow then
                    return false;
                end

                if aRow == bRow then
                    return aCol < bCol;
                end

                return aRow < bRow;
            end);
            self.cache.orderedTreeNodes[treeID] = nodes;
        end

        return CopyTable(self.cache.orderedTreeNodes[treeID]);
    end
    if not self.cache.treeNodes or not self.cache.treeNodes[treeID] then
        self.cache.treeNodes[treeID] = C_Traits.GetTreeNodes(treeID);
    end

    return CopyTable(self.cache.treeNodes[treeID]);
end

--- @param spellID number
--- @return (nil|number, nil|number) nodeID, entryID - nil if not found or error
function TLM:GetNodeAndEntryBySpellID(spellID, classID, specID)
    if
        not self.cache.spellNodeMap
        or not self.cache.spellNodeMap[classID]
        or not self.cache.spellNodeMap[classID][specID]
    then
        self.cache.spellNodeMap[classID] = self.cache.spellNodeMap[classID] or {};
        self.cache.spellNodeMap[classID][specID] = self.cache.spellNodeMap[classID][specID] or {};

        local treeID = LibTT:GetClassTreeId(classID);
        local nodes = self:GetTreeNodes(treeID);
        for _, nodeID in pairs(nodes) do
            local nodeInfo = LibTT:IsNodeVisibleForSpec(specID, nodeID) and LibTT:GetNodeInfo(treeID, nodeID);
            if nodeInfo and nodeInfo.entryIDs then
                for _, entryID in pairs(nodeInfo.entryIDs) do
                    local entryInfo = LibTT:GetEntryInfo(treeID, entryID);
                    if entryInfo and entryInfo.definitionID then
                        local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID);
                        if definitionInfo.spellID then
                            self.cache.spellNodeMap[classID][specID][definitionInfo.spellID] = {
                                nodeID = nodeID,
                                entryID = entryID,
                            };
                        end
                    elseif entryInfo and entryInfo.subTreeID then
                        self.cache.spellNodeMap[classID][specID][entryInfo.subTreeID] = {
                            nodeID = nodeID,
                            entryID = entryID,
                        };
                    end
                end
            end
        end
    end

    local result = self.cache.spellNodeMap[classID][specID][spellID];
    if result then
        return result.nodeID, result.entryID;
    end
end

--- @param nodeID number?
--- @return boolean? # nil if nodeID or configID is nil
function TLM:IsChoiceNode(nodeID)
    local configID = C_ClassTalents.GetActiveConfigID();
    if configID == nil or nodeID == nil then return; end

    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
    return nodeInfo and (Enum.TraitNodeType.Selection == nodeInfo.type or Enum.TraitNodeType.SubTreeSelection == nodeInfo.type);
end

--- @return number incremented unique ID
function TLM:IncrementCustomLoadoutAutoIncrement()
    self.db.customLoadoutAutoIncrement = self.db.customLoadoutAutoIncrement + 1;

    return self.db.customLoadoutAutoIncrement;
end

function TLM:GetBlizzardLoadoutSpec(configID)
    for index = 1, GetNumSpecializations() do
        local specID = GetSpecializationInfo(index);
        for _, specConfigID in pairs(C_ClassTalents.GetConfigIDsBySpecID(specID)) do
            if specConfigID == configID then
                return specID;
            end
        end
    end
end

function TLM:UpdateBlizzardLoadouts()
    local classID = self.playerClassID;
    self.db.blizzardLoadouts[classID] = self.db.blizzardLoadouts[classID] or {};
    for index = 1, GetNumSpecializations() do
        local specID = GetSpecializationInfo(index);
        self.db.blizzardLoadouts[classID][specID] = self.db.blizzardLoadouts[classID][specID] or {};
        if self.db.blizzardLoadouts[classID][specID][self.playerName] then
            for configID, _ in pairs(self.db.blizzardLoadouts[classID][specID][self.playerName]) do
                self.cache.loadoutByID[configID] = nil;
            end
        end
        self.db.blizzardLoadouts[classID][specID][self.playerName] = {};

        local activeConfigID = C_ClassTalents.GetActiveConfigID();
        for _, configID in pairs(C_ClassTalents.GetConfigIDsBySpecID(specID)) do
            if configID ~= activeConfigID and configID ~= self.charDb.customLoadoutConfigID then
                self:UpdateBlizzardLoadout(configID, specID);
            end
        end
    end
    self:TriggerEvent(self.Event.LoadoutListUpdated);
end

function TLM:UpdateBlizzardLoadout(configID, specID)
    local classID = self.playerClassID;
    specID = specID or self:GetBlizzardLoadoutSpec(configID);
    if not specID then return; end

    self.db.blizzardLoadouts[classID] = self.db.blizzardLoadouts[classID] or {};
    self.db.blizzardLoadouts[classID][specID] = self.db.blizzardLoadouts[classID][specID] or {};
    self.db.blizzardLoadouts[classID][specID][self.playerName] = self.db.blizzardLoadouts[classID][specID][self.playerName] or {};

    local configInfo = C_Traits.GetConfigInfo(configID);
    if not configInfo or configInfo.type ~= Enum.TraitConfigType.Combat then return; end

    local serialized = self:SerializeLoadout(configID, specID);
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
        self.cache.loadoutByID[configID] = displayInfo;
        self:TriggerEvent(self.Event.LoadoutUpdated, classID, specID, configID, displayInfo);
    else
        self:Print("Failed to serialize loadout " .. configID);
    end
end

--- @param customLoadoutID number|string
--- @param selectedNodes string
--- @param levelingOrder string|nil
--- @param classIDOrNil number|nil - if nil, the player's class is used
--- @param specIDOrNil number|nil - if nil, the player's spec is used
function TLM:UpdateCustomLoadout(customLoadoutID, selectedNodes, levelingOrder, classIDOrNil, specIDOrNil)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;
    local loadoutInfo = self.db.customLoadouts[classID]
        and self.db.customLoadouts[classID][specID]
        and self.db.customLoadouts[classID][specID][customLoadoutID];

    if loadoutInfo then
        loadoutInfo.selectedNodes = selectedNodes;
        loadoutInfo.levelingOrder = levelingOrder;

        local namePrefix = loadoutInfo.levelingOrder and CreateAtlasMarkup("GarrMission_CurrencyIcon-Xp", 16, 16) or "";
        local displayInfo = {
            id = customLoadoutID,
            displayName = namePrefix .. loadoutInfo.name,
            loadoutInfo = loadoutInfo,
            owner = nil,
            playerIsOwner = true,
            isBlizzardLoadout = false,
            parentMapping = self:GetParentMappingForLoadout(loadoutInfo, specID),
            classID = classID,
            specID = specID,
        }
        self.cache.loadoutByID[customLoadoutID] = displayInfo;
        self:TriggerEvent(self.Event.LoadoutUpdated, classID, specID, customLoadoutID, displayInfo);
    end
end

--- @param configID number
--- @return string|false serialized loadout
function TLM:SerializeLoadout(configID, specID)
    specID = specID or self.playerSpecID;
    local importString = ImportExport:TryExportBlizzardLoadoutToString(configID, specID);
    if importString and importString ~= "" then
        return (self:BuildSerializedSelectedNodesFromImportString(importString));
    end
    local serialized = "";
    --- format: nodeID_entryID_spellIDOrSubTreeID_rank
    local vSep = SERIALIZATION_VALUE_SEPARATOR;
    local nSep = SERIALIZATION_NODE_SEPARATOR;
    local formatString = "%d" .. vSep .. "%d" .. vSep .. "%d" .. vSep .. "%d" .. nSep;

    local treeID = self:GetTreeID();
    local nodes = self:GetTreeNodes(treeID);
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
            elseif entryInfo and entryInfo.subTreeID then
                serialized = serialized .. string.format(
                    formatString,
                    nodeID,
                    entryID,
                    entryInfo.subTreeID,
                    nodeInfo.ranksPurchased
                );
            end
        end
    end

    return serialized;
end

--- @param serialized string
--- @return table<number, TLM_DeserializedLoadout> [nodeID] = deserializedNode
function TLM:DeserializeLoadout(serialized)
    if self.cache.deserializationCache[serialized] then
        return CopyTable(self.cache.deserializationCache[serialized]);
    end
    local loadout = {};
    local vSep = SERIALIZATION_VALUE_SEPARATOR;
    local nSep = SERIALIZATION_NODE_SEPARATOR;

    for node in string.gmatch(serialized, "([^" .. nSep .. "]+)") do
        --- format: nodeID_entryID_spellIDOrSubTreeID_rank
        local nodeID, entryID, spellID, rank = string.split(vSep, node);
        --- @type TLM_DeserializedLoadout
        loadout[tonumber(nodeID)] = {
            nodeID = tonumber(nodeID),
            entryID = tonumber(entryID),
            spellID = tonumber(spellID),
            rank = tonumber(rank),
        };
    end

    self.cache.deserializationCache[serialized] = loadout;

    return CopyTable(loadout);
end

--- @param serialized string
--- @return TLM_LevelingBuildEntry_withLevel[] # an unordered list of entries
function TLM:DeserializeLevelingOrder(serialized)
    if self.cache.deserializationLevelingCache[serialized] then
        return CopyTable(self.cache.deserializationLevelingCache[serialized]);
    end
    local loadout = {};
    local vSep = SERIALIZATION_VALUE_SEPARATOR;
    local nSep = SERIALIZATION_NODE_SEPARATOR;
    local i = 0;

    for node in string.gmatch(serialized, "([^" .. nSep .. "]+)") do
        --- format: level_nodeID_targetRank
        local level, nodeID, targetRank = string.split(vSep, node);
        i = i + 1;
        --- @type TLM_LevelingBuildEntry_withLevel
        loadout[i] = {
            level = tonumber(level), ---@diagnostic disable-line: assign-type-mismatch
            nodeID = tonumber(nodeID), ---@diagnostic disable-line: assign-type-mismatch
            targetRank = tonumber(targetRank), ---@diagnostic disable-line: assign-type-mismatch
        };
    end
    self.cache.deserializationLevelingCache[serialized] = loadout;

    return CopyTable(loadout);
end

--- @return string|number|nil currently active (possibly custom) loadout ID, custom loadouts are prefixed with "C_"
function TLM:GetActiveLoadoutID()
    local activeLoadoutConfigID = self:GetActiveBlizzardLoadoutConfigID();
    local customLoadoutID = self.charDb.selectedCustomLoadoutID[self.playerSpecID];
    if customLoadoutID then
        local customLoadout = self:GetLoadoutByID(customLoadoutID, true);
        local parentConfigID = self:GetParentMappingForLoadout(customLoadout, self.playerSpecID)[0];

        if activeLoadoutConfigID == parentConfigID then
            return customLoadoutID;
        end
    end

    return activeLoadoutConfigID;
end

--- @param loadoutInfo TLM_LoadoutInfo
--- @return table<number, TLM_LoadoutEntryInfo> # [nodeID] = entryInfo
--- @return number # total number of entries (including those that could not be matched)
--- @return number # number of entries that could not be matched
function TLM:LoadoutInfoToEntryInfo(loadoutInfo)
    local configID = C_ClassTalents.GetActiveConfigID();
    local entryInfo = {};
    local foundIssues = 0;
    local totalEntries = 0;
    local deserialized = self:DeserializeLoadout(loadoutInfo.selectedNodes);

    for _, loadoutNodeInfo in pairs(deserialized) do
        totalEntries = totalEntries + 1;
        local nodeInfoExists = false;
        local isChoiceNode = false;
        local nodeInfo = C_Traits.GetNodeInfo(configID, loadoutNodeInfo.nodeID);
        if nodeInfo then
            for _, entryID in pairs(nodeInfo.entryIDs) do
                if entryID == loadoutNodeInfo.entryID then
                    nodeInfoExists = true;
                    isChoiceNode = Enum.TraitNodeType.Selection == nodeInfo.type or Enum.TraitNodeType.SubTreeSelection == nodeInfo.type;
                    break;
                else
                    local nodeEntryInfo = C_Traits.GetEntryInfo(configID, entryID);
                    local definitionInfo = nodeEntryInfo and nodeEntryInfo.definitionID and C_Traits.GetDefinitionInfo(nodeEntryInfo.definitionID);
                    if definitionInfo and definitionInfo.spellID == loadoutNodeInfo.spellID then
                        nodeInfoExists = true;
                        loadoutNodeInfo.entryID = entryID;
                        isChoiceNode = Enum.TraitNodeType.Selection == nodeInfo.type or Enum.TraitNodeType.SubTreeSelection == nodeInfo.type;
                        break;
                    elseif nodeEntryInfo and nodeEntryInfo.subTreeID == loadoutNodeInfo.spellID then
                        nodeInfoExists = true;
                        loadoutNodeInfo.entryID = entryID;
                        isChoiceNode = Enum.TraitNodeType.Selection == nodeInfo.type or Enum.TraitNodeType.SubTreeSelection == nodeInfo.type;
                        break;
                    end
                end
            end
        end

        local nodeID, entryID = loadoutNodeInfo.nodeID, loadoutNodeInfo.entryID;
        if not nodeInfoExists then
            nodeID, entryID = self:GetNodeAndEntryBySpellID(loadoutNodeInfo.spellID, self.playerClassID, self.playerSpecID);
            isChoiceNode = self:IsChoiceNode(nodeID) or false;
        end
        if nodeID and entryID then
            if entryInfo[nodeID] then -- duplicate nodeID
                if
                    entryInfo[nodeID].selectionEntryID == entryID
                    and entryInfo[nodeID].ranksPurchased == loadoutNodeInfo.rank
                    and entryInfo[nodeID].isChoiceNode == isChoiceNode
                then
                    -- duplicate entry, ignore
                    totalEntries = totalEntries - 1;
                else
                    foundIssues = foundIssues + 1;
                end
            end
            --- @type TLM_LoadoutEntryInfo
            entryInfo[nodeID] = {
                selectionEntryID = entryID,
                nodeID = nodeID,
                ranksPurchased = loadoutNodeInfo.rank,
                isChoiceNode = isChoiceNode,
            };
        else
            foundIssues = foundIssues + 1;
        end
    end

    return entryInfo, totalEntries, foundIssues;
end

--- @param loadoutID string|number
--- @param rawData boolean|nil - if true, the raw saved variable information is returned
--- @return TLM_LoadoutDisplayInfo|nil
function TLM:GetLoadoutByID(loadoutID, rawData)
    local displayInfo = self.cache.loadoutByID[loadoutID];
    if rawData then return displayInfo; end

    if displayInfo then
        displayInfo = Mixin({}, displayInfo);
        displayInfo.isActive = self:GetActiveLoadoutID() == loadoutID;
    end

    return displayInfo;
end

--- @return TLM_LoadoutDisplayInfo[] - list of all loadouts, isActive still refers to the current player only
function TLM:GetAllLoadouts()
    local loadouts = {};
    local activeLoadoutID = self:GetActiveLoadoutID();
    for loadoutID, displayInfo in pairs(self.cache.loadoutByID) do
        displayInfo = Mixin({}, displayInfo);
        displayInfo.isActive = activeLoadoutID == loadoutID;
        table.insert(loadouts, displayInfo);
    end

    return loadouts;
end

--- @return TLM_LoadoutDisplayInfo[] - list of loadouts
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

--- @param loadoutInfo TLM_LoadoutInfo
function TLM:ApplyCustomLoadout(loadoutInfo, autoApply)
    --------------------------------------------------------------------------------------------
    --- If autoApply is false, simply reset and load the custom loadout.
    ---
    --- plan A:
    --- note: this plan failed :( the game doesn't really support making changes to a loadout in the background, and then loading that
    --- 1. Reset tree of the parentConfigID
    --- 2.
    ---    if a configID other than parentConfigID is active:
    ---      - LoadConfigByPredicate to parentConfigID
    ---    else:
    ---      - C_ClassTalents.LoadConfig(parentConfigID, true)
    --- 3. Apply the custom loadout to activeConfigID (but don't commit)
    --- 4. Commit activeConfigID
    --- 5. After cast is done, C_ClassTalents.SaveConfig(parentConfigID)
    ---
    ---
    --- plan B:
    --- note: this plan is a bit shitty, but it seems to work.. for now..
    --- 1. switch to parentConfigID first
    --- 2. after switching, reset tree and apply custom loadout to activeConfigID
    --- 3. commit activeConfigID, but only if there are staging changes
    ---
    --- plan C:
    --- note: this ?might? work? it's hard to tell, there're some small annoying issues, but they're hard to reproduce and pin down
    --- 1. if currentBlizzConfig ~= parentConfigID -> C_ClassTalents.LoadConfig(parentConfigID, autoApply: false)
    --- 2. Reset parentConfigID tree
    --- 3. Apply custom loadout to activeConfigID
    --- 4. Commit activeConfigID
    --- 5. After cast is done, C_ClassTalents.SaveConfig(parentConfigID)
    ---
    --------------------------------------------------------------------------------------------

    local specID = self.playerSpecID;
    local parentConfigID = self:GetParentMappingForLoadout(loadoutInfo, specID)[0];
    local activeConfigID = C_ClassTalents.GetActiveConfigID();
    if not activeConfigID then
        self:Print("You have not unlocked talents yet.");

        return false;
    end

    do
        local ok, configInfo = pcall(C_Traits.GetConfigInfo, parentConfigID);
        if not ok or not configInfo then
            self:SetParentLoadout(loadoutInfo.id, nil);
            parentConfigID = self:GetParentMappingForLoadout(loadoutInfo, specID)[0];
            if parentConfigID then
                ok, configInfo = pcall(C_Traits.GetConfigInfo, parentConfigID);
                if not ok or not configInfo then
                    self.charDb.customLoadoutConfigID[specID] = nil;
                    parentConfigID = nil;
                end
            end
        end
    end
    self:SetParentLoadout(loadoutInfo.id, parentConfigID);

    if autoApply and parentConfigID == nil then
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
    local loadoutEntryInfo, entriesCount, foundIssues = self:LoadoutInfoToEntryInfo(loadoutInfo);
    local levelingOrder = loadoutInfo.levelingOrder and self:DeserializeLevelingOrder(loadoutInfo.levelingOrder) or nil;

    if autoApply and self:GetActiveBlizzardLoadoutConfigID() ~= parentConfigID then
        self:ApplyBlizzardLoadout(parentConfigID, true, function()
            RunNextFrame(function() self:ApplyCustomLoadout(loadoutInfo, autoApply); end);
        end);

        return true;
    end
    local entriesPurchased = self:ResetAndPurchaseLoadoutEntries(activeConfigID, loadoutEntryInfo, levelingOrder);
    entriesCount = entriesCount - entriesPurchased;
    local currencyInfos = C_Traits.GetTreeCurrencyInfo(activeConfigID, self:GetTreeID(), false);
    local hasAvailableCurrency = false;
    for _, currencyInfo in pairs(currencyInfos) do
        hasAvailableCurrency = hasAvailableCurrency or currencyInfo.quantity > 0;
    end
    if hasAvailableCurrency and entriesCount > 0 then
        self:Print("Failed to fully apply loadout. " .. entriesCount .. " entries could not be purchased.");
    end

    if autoApply and C_Traits.ConfigHasStagedChanges(activeConfigID) and not C_ClassTalents.CommitConfig(parentConfigID) then
        self:Print("Failed to commit loadout.");
        return false;
    end
    --- @type Frame|nil
    local talentsTab = ClassTalentFrame and ClassTalentFrame.TalentsTab; ---@diagnostic disable-line: undefined-global
    local talentsTabIsVisible = talentsTab and talentsTab.IsVisible and talentsTab:IsVisible();
    if autoApply and talentsTab and talentsTabIsVisible then
        local stagedNodes = C_Traits.GetStagedPurchases(activeConfigID);
        if next(stagedNodes) then
            talentsTab.stagedPurchaseNodes = C_Traits.GetStagedPurchases(activeConfigID);
            talentsTab:SetCommitVisualsActive(true, TalentFrameBaseMixin.VisualsUpdateReasons.CommitOngoing, true);
        end
    end

    self.charDb.selectedCustomLoadoutID[self.playerSpecID] = loadoutInfo.id;
    local namePrefix = loadoutInfo.levelingOrder and CreateAtlasMarkup("GarrMission_CurrencyIcon-Xp", 16, 16) or "";
    local displayInfo = {
        id = loadoutInfo.id,
        displayName = namePrefix .. loadoutInfo.name,
        loadoutInfo = loadoutInfo,
        owner = nil,
        playerIsOwner = true,
        isBlizzardLoadout = false,
        parentMapping = self:GetParentMappingForLoadout(loadoutInfo, self.playerSpecID),
        classID = self.playerClassID,
        specID = self.playerSpecID,
    }
    self:TriggerEvent(self.Event.CustomLoadoutApplied, self.playerClassID, specID, loadoutInfo.id, displayInfo);

    return true;
end

--- @param configID number
--- @param loadoutEntryInfo table<number, TLM_LoadoutEntryInfo> # [nodeID] = entryInfo
--- @param levelingOrder TLM_LevelingBuildEntry_withLevel[]|nil # unordered list of entries
--- @return number number of removed entries (due to successful purchases)
function TLM:ResetAndPurchaseLoadoutEntries(configID, loadoutEntryInfo, levelingOrder)
    self:CheckForBadAddons(true);
    local totalEntriesRemoved = 0;
    C_Traits.ResetTree(configID, self:GetTreeID());
    local entriesByLevel = {};
    for _, entry in pairs(levelingOrder or {}) do
        entriesByLevel[entry.level] = entriesByLevel[entry.level] or {};
        table.insert(entriesByLevel[entry.level], entry);
    end

    while (true) do
        local removed = self:PurchaseLoadoutEntryInfo(self:GetTreeID(), configID, loadoutEntryInfo, entriesByLevel);
        if (0 == removed) then
            break;
        end
        totalEntriesRemoved = totalEntriesRemoved + removed;
    end

    return totalEntriesRemoved;
end

--- @param treeID number
--- @param configID number
--- @param loadoutEntryInfo table<number, TLM_LoadoutEntryInfo> # [nodeID] = entryInfo
--- @param entriesByLevel table<number, TLM_LevelingBuildEntry_withLevel[]>|nil # [level] = entries
--- @return number number of removed entries (due to successful purchases)
function TLM:PurchaseLoadoutEntryInfo(treeID, configID, loadoutEntryInfo, entriesByLevel)
    local removed = 0;
    local orderedNodes = self:GetTreeNodes(treeID, true);

    if entriesByLevel and next(entriesByLevel) then
        --- @type table<number, TLM_LoadoutEntryInfo>
        local notMentionedInLevelingOrder = CopyTable(loadoutEntryInfo);
        local nonZeroStartingRank = {};
        for level = 10, ns.MAX_LEVEL do
            local entries = entriesByLevel[level] or {};
            for _, entry in pairs(entries) do
                if notMentionedInLevelingOrder[entry.nodeID] and not nonZeroStartingRank[entry.nodeID] then
                    if entry.targetRank > 1 then
                        nonZeroStartingRank[entry.nodeID] = true;
                        notMentionedInLevelingOrder[entry.nodeID].ranksPurchased = entry.targetRank - 1;
                    else
                        notMentionedInLevelingOrder[entry.nodeID] = nil;
                    end
                end
            end
        end
        -- first purchase anything not mentioned in the leveling order, basically a baseline loadout
        removed = removed + (next(notMentionedInLevelingOrder) and self:PurchaseOrderedEntries(orderedNodes, configID, notMentionedInLevelingOrder) or 0);

        for level = 10, ns.MAX_LEVEL do
            local entries = entriesByLevel[level] or {};
            for _, entry in pairs(entries) do
                if loadoutEntryInfo[entry.nodeID] then
                    local nodeEntry = loadoutEntryInfo[entry.nodeID];
                    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeEntry.nodeID);
                    if nodeInfo and nodeInfo.ranksPurchased < entry.targetRank then
                        local success = false;
                        if nodeEntry.isChoiceNode then
                            success = C_Traits.SetSelection(configID, nodeEntry.nodeID, nodeEntry.selectionEntryID);
                        elseif nodeEntry.ranksPurchased then
                            success = C_Traits.PurchaseRank(configID, nodeEntry.nodeID);
                        end
                        if success then
                            nodeEntry.ranksPurchased = nodeEntry.ranksPurchased - 1;
                            if nodeEntry.ranksPurchased == 0 then
                                removed = removed + 1;
                                loadoutEntryInfo[entry.nodeID] = nil;
                            end
                        end
                    end
                end
            end
        end
        if removed > 0 then
            return removed;
        end
    end

    removed = removed + self:PurchaseOrderedEntries(orderedNodes, configID, loadoutEntryInfo);

    return removed;
end

function TLM:PurchaseOrderedEntries(orderedNodes, configID, loadoutEntryInfo)
    local removed = 0;
    for _, nodeID in ipairs(orderedNodes) do
        local nodeEntry = loadoutEntryInfo[nodeID];
        if nodeEntry then
            local success = false;
            if nodeEntry.isChoiceNode then
                success = C_Traits.SetSelection(configID, nodeEntry.nodeID, nodeEntry.selectionEntryID);
            elseif nodeEntry.ranksPurchased then
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
                for rank = 1, (nodeEntry.ranksPurchased - (nodeInfo and nodeInfo.ranksPurchased or 0)) do
                    success = C_Traits.PurchaseRank(configID, nodeEntry.nodeID);
                end
            end
            if success then
                removed = removed + 1;
                loadoutEntryInfo[nodeID] = nil;
            end
        end
    end

    return removed;
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
    self.charDb.selectedCustomLoadoutID[self.playerSpecID] = nil;
end

--- @param loadoutInfo TLM_LoadoutInfo_partial
function TLM:CreateCustomLoadoutFromLoadoutData(loadoutInfo, classIDOrNil, specIDOrNil)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;

    self.db.customLoadouts[classID] = self.db.customLoadouts[classID] or {};
    self.db.customLoadouts[classID][specID] = self.db.customLoadouts[classID][specID] or {};

    local id = "C_" .. self:IncrementCustomLoadoutAutoIncrement();
    local name = loadoutInfo.name or ('Custom Loadout ' .. id);
    --- @type TLM_LoadoutInfo
    local newLoadoutInfo = {
        id = id,
        name = name,
        selectedNodes = loadoutInfo.selectedNodes,
        levelingOrder = loadoutInfo.levelingOrder,
        parentMapping = {},
    }
    if classID == self.playerClassID and specID == self.playerSpecID then
        newLoadoutInfo.parentMapping[self.playerName] = self:GetActiveBlizzardLoadoutConfigID();
    end
    self.db.customLoadouts[classID][specID][id] = newLoadoutInfo;
    local namePrefix = newLoadoutInfo.levelingOrder and CreateAtlasMarkup("GarrMission_CurrencyIcon-Xp", 16, 16) or "";
    --- @type TLM_LoadoutDisplayInfo
    local displayInfo = {
        id = id,
        displayName = namePrefix .. newLoadoutInfo.name,
        loadoutInfo = newLoadoutInfo,
        owner = nil,
        playerIsOwner = true,
        isBlizzardLoadout = false,
        parentMapping = self:GetParentMappingForLoadout(newLoadoutInfo, specID),
        classID = classID,
        specID = specID,
    }
    self.cache.loadoutByID[id] = displayInfo;
    self:TriggerEvent(self.Event.LoadoutUpdated, classID, specID, id, displayInfo);
    self:TriggerEvent(self.Event.LoadoutListUpdated);

    return newLoadoutInfo;
end

--- @return TLM_LoadoutInfo|false false on errors
--- @return string|nil error message on errors
function TLM:CreateCustomLoadoutFromImportString(importString, autoApply, name, validateClassAndSpec, load)
    local classIDOrNil, specIDOrNil;
    if validateClassAndSpec then
        classIDOrNil, specIDOrNil = self.playerClassID, self.playerSpecID;
    end
    local selectedNodes, errorOrLevelingOrder, classID, specID = self:BuildSerializedSelectedNodesFromImportString(importString, classIDOrNil, specIDOrNil);
    if selectedNodes then
        --- @type TLM_LoadoutInfo_partial
        local loadoutInfo = {
            name = name,
            selectedNodes = selectedNodes,
            levelingOrder = errorOrLevelingOrder,
        }
        loadoutInfo = self:CreateCustomLoadoutFromLoadoutData(loadoutInfo, classID, specID);
        if load and classID == self.playerClassID and specID == self.playerSpecID then
            self:ApplyCustomLoadout(loadoutInfo, autoApply);
        end

        return loadoutInfo;
    end
    return false, errorOrLevelingOrder;
end

function TLM:CreateCustomLoadoutFromActiveTalents(name, classIDOrNil, specIDOrNil)
    local classID = tonumber(classIDOrNil) or self.playerClassID;
    local specID = tonumber(specIDOrNil) or self.playerSpecID;
    local selectedNodes = self:SerializeLoadout(C_ClassTalents.GetActiveConfigID(), specID);
    --- @type TLM_LoadoutInfo_partial
    local loadoutInfo = {
        name = name,
        selectedNodes = selectedNodes,
        levelingOrder = nil,
    }
    loadoutInfo = self:CreateCustomLoadoutFromLoadoutData(loadoutInfo, classID, specID);
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

        local namePrefix = loadoutInfo.levelingOrder and CreateAtlasMarkup("GarrMission_CurrencyIcon-Xp", 16, 16) or "";
        local displayInfo = {
            id = loadoutID,
            displayName = namePrefix .. loadoutInfo.name,
            loadoutInfo = loadoutInfo,
            owner = nil,
            playerIsOwner = true,
            isBlizzardLoadout = false,
            parentMapping = self:GetParentMappingForLoadout(loadoutInfo, specID),
            classID = classID,
            specID = specID,
        }
        self.cache.loadoutByID[loadoutID] = displayInfo;
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
        self.cache.loadoutByID[loadoutID] = nil;

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

    self.cache.loadoutByID[configID] = nil;
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

function TLM:RemoveStoredBlizzardLoadout(classID, specID, owner, configID)
    if
        self.db.blizzardLoadouts[classID]
        and self.db.blizzardLoadouts[classID][specID]
        and self.db.blizzardLoadouts[classID][specID][owner]
        and self.db.blizzardLoadouts[classID][specID][owner][configID]
    then
        self.db.blizzardLoadouts[classID][specID][owner][configID] = nil;

        self:TriggerEvent(self.Event.LoadoutListUpdated);
    end
end

--- @param classID number|string
--- @param specID number|string
--- @param loadoutInfo TLM_LoadoutInfo
--- @param excludeLevelingString boolean|nil
function TLM:ExportLoadoutToString(classID, specID, loadoutInfo, excludeLevelingString)
    --- @type number
    classID = tonumber(classID); ---@diagnostic disable-line: assign-type-mismatch
    --- @type number
    specID = tonumber(specID); ---@diagnostic disable-line: assign-type-mismatch

    --- @type number?
    local configID = (type(loadoutInfo.id) == 'number') and loadoutInfo.id or nil; ---@diagnostic disable-line: assign-type-mismatch
    local importString = configID and ImportExport:TryExportBlizzardLoadoutToString(configID, specID);
    if importString and importString ~= "" then
        return importString;
    end

    self.cache.exportStrings[classID] = self.cache.exportStrings[classID] or {};
    self.cache.exportStrings[classID][specID] = self.cache.exportStrings[classID][specID] or {};
    local key = loadoutInfo.selectedNodes .. '-LVL-' .. (loadoutInfo.levelingOrder or '');
    if not self.cache.exportStrings[classID][specID][key] then
        local deserialized = self:DeserializeLoadout(loadoutInfo.selectedNodes);
        local deserializedLevelingOrder = not excludeLevelingString and loadoutInfo.levelingOrder and self:DeserializeLevelingOrder(loadoutInfo.levelingOrder) or nil;

        self.cache.exportStrings[classID][specID][key] = ImportExport:ExportLoadoutToString(classID, specID, deserialized, deserializedLevelingOrder);
    end

    return self.cache.exportStrings[classID][specID][key];
end

--- @param importText string
--- @param expectedClassID number|nil # if classID from the importText does not match this, the import will fail
--- @param expectedSpecID number|nil # if specID from the importText does not match this, the import will fail
--- @return string|false # false on failure, serializedSelectedNodes on success
--- @return string|nil # error message on failure, serializedLevelingOrder (if any) on success
--- @return number|nil # actual classID on success
--- @return number|nil # actual specID on success
function TLM:BuildSerializedSelectedNodesFromImportString(importText, expectedClassID, expectedSpecID)
    if IcyVeinsImport:IsTalentUrl(importText) then
        return IcyVeinsImport:BuildSerializedSelectedNodesFromUrl(importText, expectedClassID, expectedSpecID);
    end

    return ImportExport:BuildSerializedSelectedNodesFromImportString(importText, expectedClassID, expectedSpecID);
end

local printedWarning = {};
--- @param printToChat boolean|nil # if true, a warning will be printed to chat if any bad addons are found
--- @return table<string, string> # [addonName] = warning text
function TLM:CheckForBadAddons(printToChat)
    local badAddons = {};
    -- zygor guides
    if
        ZygorGuidesViewer
        and ZygorGuidesViewer.db
        and ZygorGuidesViewer.db.profile
        and ZygorGuidesViewer.db.profile.talenton
    then
        badAddons['ZygorGuidesViewer'] = 'Zygor Guides\' talent advisor is enabled. This is known to cause game freezes when changing loadouts. Disable this feature and report it to the author of Zygor Guides.';
    end

    if printToChat then
        for addon, warningText in pairs(badAddons) do
            if not printedWarning[addon] then
                printedWarning[addon] = true;
                self:Print(warningText);
            end
        end
    end

    return badAddons;
end
