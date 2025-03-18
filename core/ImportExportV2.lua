local _, ns = ...

local LOADOUT_SERIALIZATION_VERSION = 2;
if C_Traits.GetLoadoutSerializationVersion() ~= LOADOUT_SERIALIZATION_VERSION then return; end

--- @class TLM_ImportExportV2
local ImportExport = {};
ns.ImportExport = ImportExport;

local HERO_SELECTION_NODE_LEVEL = 71;
local LEVELING_BUILD_SERIALIZATION_VERSION = 2;
local LEVELING_EXPORT_STRING_PATERN = "%s-LVL-%s";

local LEVELING_BIT_WIDTH_VERSION = 5;
local LEVELING_BIT_WIDTH_DATA = 7; -- allows for 128 levels

local BIT_WIDTH_HEADER_VERSION = 8;
local BIT_WIDTH_SPEC_ID = 16;
local BIT_WIDTH_RANKS_PURCHASED = 6;

local LibTT = LibStub("LibTalentTree-1.0");

local nodeCache = {};
local function GetTreeNodes(treeID)
    if not nodeCache[treeID] then
        nodeCache[treeID] = C_Traits.GetTreeNodes(treeID);
    end
    return nodeCache[treeID];
end

local treeHashCache = {}
local function GetTreeHash(treeID)
    if not treeHashCache[treeID] then
        treeHashCache[treeID] = C_Traits.GetTreeHash(treeID);
    end
    return treeHashCache[treeID];
end

local specToClassMap = {};
do
    for classID = 1, GetNumClasses() do
        for specIndex = 1, GetNumSpecializationsForClassID(classID) do
            specToClassMap[(GetSpecializationInfoForClassID(classID, specIndex))] = classID;
        end
    end
end

--- @param importText string
--- @param expectedClassID number|nil # if classID from the importText does not match this, the import will fail
--- @param expectedSpecID number|nil # if specID from the importText does not match this, the import will fail
--- @return string|false # false on failure, serializedSelectedNodes on success
--- @return string|nil # error message on failure, serializedLevelingOrder (if any) on success
--- @return number|nil # actual classID on success
--- @return number|nil # actual specID on success
--- @public
function ImportExport:BuildSerializedSelectedNodesFromImportString(importText, expectedClassID, expectedSpecID)
    local importStream = ExportUtil.MakeImportDataStream(importText);

    local headerValid, serializationVersion, specIDFromString, treeHash = self:ReadLoadoutHeader(importStream);
    local classIDFromString = specToClassMap[specIDFromString];

    if(not headerValid) then
        return false, LOADOUT_ERROR_BAD_STRING;
    end

    if(serializationVersion ~= LOADOUT_SERIALIZATION_VERSION) then
        return false, LOADOUT_ERROR_SERIALIZATION_VERSION_MISMATCH;
    end

    if(expectedSpecID and specIDFromString ~= expectedSpecID) then
        return false, LOADOUT_ERROR_WRONG_SPEC;
    end

    if(expectedClassID and classIDFromString ~= expectedClassID) then
        return false, "Wrong class";
    end

    local treeID = LibTT:GetClassTreeID(classIDFromString);
    if not treeID or not self:IsHashValid(treeHash, treeID) then
        return false, LOADOUT_ERROR_TREE_CHANGED;
    end

    local loadoutContent = self:ReadLoadoutContent(importStream, treeID);

    local serialized = "";
    --- format: nodeID_entryID_spellIDOrSubTreeID_rank
    local vSep = ns.SERIALIZATION_VALUE_SEPARATOR;
    local nSep = ns.SERIALIZATION_NODE_SEPARATOR;
    local formatString = "%d" .. vSep .. "%d" .. vSep .. "%d" .. vSep .. "%d" .. nSep;

    local nodes = GetTreeNodes(treeID);
    for i, nodeID in pairs(nodes) do
        local indexInfo = loadoutContent[i];
        if indexInfo.isNodePurchased then
            local nodeInfo = LibTT:GetNodeInfo(nodeID);
            local entryID = indexInfo.isChoiceNode and nodeInfo.entryIDs[indexInfo.choiceNodeSelection] or nodeInfo.entryIDs[1];
            local entryInfo = entryID and LibTT:GetEntryInfo(entryID);
            if entryInfo and entryInfo.definitionID then
                local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID);
                if definitionInfo and definitionInfo.spellID then
                    serialized = serialized .. string.format(
                        formatString,
                        nodeID,
                        entryID,
                        definitionInfo.spellID,
                        indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or nodeInfo.maxRanks
                    );
                end
            elseif entryInfo and entryInfo.subTreeID then
                serialized = serialized .. string.format(
                    formatString,
                    nodeID,
                    entryID,
                    entryInfo.subTreeID,
                    indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or nodeInfo.maxRanks
                );
            end
        end
    end

    local serializedLevelingOrder = nil;
    local _, _, _, levelingBuildString = importText:find(LEVELING_EXPORT_STRING_PATERN:format("(.*)", "(.*)"):gsub("%-", "%%-"));
    if levelingBuildString then
        local levelingImportStream = ExportUtil.MakeImportDataStream(levelingBuildString);
        local levelingHeaderValid, levelingSerializationVersion = self:ReadLevelingExportHeader(levelingImportStream);
        if levelingHeaderValid and levelingSerializationVersion == LEVELING_BUILD_SERIALIZATION_VERSION then
            local loadoutEntryInfo = self:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent);
            local levelingBuild = self:ReadLevelingBuildContent(levelingImportStream, loadoutEntryInfo);

            serializedLevelingOrder = "";
            --- format: level_nodeID_targetRank
            local lvlingFormatString = "%d" .. vSep .. "%d" .. vSep .. "%d" .. nSep;
            for _, entries in pairs(levelingBuild.entries) do
                for level, entry in pairs(entries) do
                    serializedLevelingOrder = serializedLevelingOrder .. string.format(
                        lvlingFormatString,
                        level,
                        entry.nodeID,
                        entry.targetRank
                    );
                end
            end
            if levelingBuild.selectedSubTreeID then
                local nodeID, _ = LibTT:GetSubTreeSelectionNodeIDAndEntryIDBySpecID(specIDFromString, levelingBuild.selectedSubTreeID);
                serializedLevelingOrder = serializedLevelingOrder .. string.format(
                    lvlingFormatString,
                    HERO_SELECTION_NODE_LEVEL,
                    nodeID,
                    1
                );
            end
        end
    end

    return serialized, serializedLevelingOrder, classIDFromString, specIDFromString;
end

--- @private
function ImportExport:ReadLoadoutHeader(importStream)
    local headerBitWidth = BIT_WIDTH_HEADER_VERSION + BIT_WIDTH_SPEC_ID + 128;
    local importStreamTotalBits = importStream:GetNumberOfBits();
    if( importStreamTotalBits < headerBitWidth) then
        return false, 0, 0, 0;
    end
    local serializationVersion = importStream:ExtractValue(BIT_WIDTH_HEADER_VERSION);
    local specID = importStream:ExtractValue(BIT_WIDTH_SPEC_ID);

    -- treeHash is a 128bit hash, passed as an array of 16, 8-bit values
    local treeHash = {};
    for i=1,16,1 do
        treeHash[i] = importStream:ExtractValue(8);
    end
    return true, serializationVersion, specID, treeHash;
end

--- @private
function ImportExport:ReadLevelingExportHeader(importStream)
    local headerBitWidth = LEVELING_BIT_WIDTH_VERSION;
    local importStreamTotalBits = importStream:GetNumberOfBits();
    if( importStreamTotalBits < headerBitWidth) then
        return false, 0;
    end
    local serializationVersion = importStream:ExtractValue(LEVELING_BIT_WIDTH_VERSION);

    return true, serializationVersion;
end

--- @private
function ImportExport:IsHashValid(treeHash, treeID)
    if not #treeHash == 16 then
        return false;
    end
    local expectedHash = GetTreeHash(treeID);
    local allZero = true;
    for i, value in ipairs(treeHash) do
        if value ~= 0 then
            allZero = false;
        end
        if not allZero and value ~= expectedHash[i] then
            return false;
        end
    end

    return true;
end

--- @private
function ImportExport:ReadLoadoutContent(importStream, treeID)
    local results = {};

    local treeNodes = GetTreeNodes(treeID);
    for i, nodeID in ipairs(treeNodes) do
        local nodeSelectedValue = importStream:ExtractValue(1);
        local isNodeSelected =  nodeSelectedValue == 1;
        local isNodePurchased = false;
        local isPartiallyRanked = false;
        local partialRanksPurchased = 0;
        local isChoiceNode = false;
        local choiceNodeSelection = 0;

        if(isNodeSelected) then
            local nodePurchasedValue = importStream:ExtractValue(1);

            isNodePurchased = nodePurchasedValue == 1;
            if(isNodePurchased) then
                local isPartiallyRankedValue = importStream:ExtractValue(1);
                isPartiallyRanked = isPartiallyRankedValue == 1;
                if(isPartiallyRanked) then
                    partialRanksPurchased = importStream:ExtractValue(BIT_WIDTH_RANKS_PURCHASED);
                end
                local isChoiceNodeValue = importStream:ExtractValue(1);
                isChoiceNode = isChoiceNodeValue == 1;
                if(isChoiceNode) then
                    choiceNodeSelection = importStream:ExtractValue(2);
                end
            end
        end

        local result = {};
        result.isNodeSelected = isNodeSelected;
        result.isNodeGranted = isNodeSelected and not isNodePurchased;
        result.isNodePurchased = isNodePurchased;
        result.isPartiallyRanked = isPartiallyRanked;
        result.partialRanksPurchased = partialRanksPurchased;
        result.isChoiceNode = isChoiceNode;
        -- entry index is stored as zero-index, so convert back to lua index
        result.choiceNodeSelection = choiceNodeSelection + 1;
        result.nodeID = nodeID;
        results[i] = result;
    end

    return results;
end

--- @param loadoutEntryInfo TLM_LoadoutEntryInfo[]
--- @return TLM_LevelingBuild
--- @private
function ImportExport:ReadLevelingBuildContent(importStream, loadoutEntryInfo)
    local results = {};
    local selectedSubTreeID;

    for _, entry in ipairs(loadoutEntryInfo) do
        local nodeInfo = LibTT:GetNodeInfo(entry.nodeID);
        local ranksPurchased = entry.ranksPurchased;
        for rank = 1, ranksPurchased do
            local success, level = pcall(importStream.ExtractValue, importStream, LEVELING_BIT_WIDTH_DATA);
            if not success or not level then -- end of stream
                return { entries = results, selectedSubTreeID = selectedSubTreeID };
            end
            if level > 0 and not nodeInfo.isSubTreeSelection then
                local result = {};
                result.nodeID = entry.nodeID;
                result.entryID = entry.isChoiceNode and entry.selectionEntryID;
                result.targetRank = rank;

                local tree = nodeInfo.subTreeID or (nodeInfo.isClassNode and 1 or 2);
                results[tree] = results[tree] or {};
                results[tree][level] = result;
            elseif nodeInfo.isSubTreeSelection then
                local entryInfo = LibTT:GetEntryInfo(entry.selectionEntryID);
                if entryInfo and entryInfo.subTreeID then
                    selectedSubTreeID = entryInfo.subTreeID;
                end
            end
        end
    end

    return { entries = results, selectedSubTreeID = selectedSubTreeID };
end

--- converts from compact bit-packing format to LoadoutEntryInfo format to pass to ImportLoadout API
--- @return TLM_LoadoutEntryInfo[]
--- @private
function ImportExport:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent)
    local results = {};
    local treeNodes = C_Traits.GetTreeNodes(treeID);
    local count = 1;
    for i, treeNodeID in ipairs(treeNodes) do

        local indexInfo = loadoutContent[i];

        if (indexInfo.isNodeSelected and not indexInfo.isNodeGranted) then
            local treeNode = LibTT:GetNodeInfo(treeNodeID);
            local isChoiceNode = treeNode.type == Enum.TraitNodeType.Selection or treeNode.type == Enum.TraitNodeType.SubTreeSelection;
            local choiceNodeSelection = indexInfo.isChoiceNode and indexInfo.choiceNodeSelection or nil;
            if indexInfo.isNodeSelected and isChoiceNode ~= indexInfo.isChoiceNode then
                -- guard against corrupt import strings
                print(string.format('Import string is corrupt, node type mismatch at nodeID %d. First option will be selected.', treeNodeID));
                choiceNodeSelection = 1;
            end
            --- @type TLM_LoadoutEntryInfo
            local result = {
                nodeID = treeNode.ID,
                ranksPurchased = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or treeNode.maxRanks,
                selectionEntryID = (indexInfo.isNodeSelected and isChoiceNode and treeNode.entryIDs[choiceNodeSelection]) or (treeNode.activeEntry and treeNode.activeEntry.entryID),
                isChoiceNode = isChoiceNode,
            };
            results[count] = result;
            count = count + 1;
        end

    end

    return results;
end

--- @public
function ImportExport:TryExportBlizzardLoadoutToString(configID, specID)
    local loadoutString = C_Traits.GenerateImportString(configID);
    if not loadoutString or '' == loadoutString then
        return nil;
    end

    local exportStream = ExportUtil.MakeExportDataStream();
    local importStream = ExportUtil.MakeImportDataStream(loadoutString);

    if importStream:ExtractValue(BIT_WIDTH_HEADER_VERSION) ~= LOADOUT_SERIALIZATION_VERSION then
        return nil;
    end

    local headerSpecID = importStream:ExtractValue(BIT_WIDTH_SPEC_ID);
    if headerSpecID == specID then
        return loadoutString; -- no update needed
    end

    exportStream:AddValue(BIT_WIDTH_HEADER_VERSION, LOADOUT_SERIALIZATION_VERSION);
    exportStream:AddValue(BIT_WIDTH_SPEC_ID, specID);
    local remainingBits = importStream:GetNumberOfBits() - BIT_WIDTH_HEADER_VERSION - BIT_WIDTH_SPEC_ID;
    -- copy the remaining bits in batches of 16
    while remainingBits > 0 do
        local bitsToCopy = math.min(remainingBits, 16);
        exportStream:AddValue(bitsToCopy, importStream:ExtractValue(bitsToCopy));
        remainingBits = remainingBits - bitsToCopy;
    end

    return exportStream:GetExportString();
end

--- @param classID number
--- @param specID number
--- @param deserializedLoadout table<number, TLM_DeserializedLoadout> [nodeID] = deserializedNode
--- @param levelingBuild nil|TLM_LevelingBuildEntry_withLevel[]
--- @public
function ImportExport:ExportLoadoutToString(classID, specID, deserializedLoadout, levelingBuild)
    local exportStream = ExportUtil.MakeExportDataStream();
    local treeID = LibTT:GetClassTreeID(classID);

    -- write header
    exportStream:AddValue(BIT_WIDTH_HEADER_VERSION, LOADOUT_SERIALIZATION_VERSION);
    exportStream:AddValue(BIT_WIDTH_SPEC_ID, specID);
    -- treeHash is a 128bit hash, passed as an array of 16, 8-bit values
    -- empty tree hash will disable validation on import
    exportStream:AddValue(8 * 16, 0);

    local cleanedDeserializedLoadout = self:WriteLoadoutContent(exportStream, deserializedLoadout, treeID, classID, specID);

    local loadoutString = exportStream:GetExportString();
    if not levelingBuild or not next(levelingBuild) then
        return loadoutString
    end

    local levelingExportStream = ExportUtil.MakeExportDataStream();
    levelingExportStream:AddValue(LEVELING_BIT_WIDTH_VERSION, LEVELING_BUILD_SERIALIZATION_VERSION);
    self:WriteLevelingBuildContent(levelingExportStream, treeID, cleanedDeserializedLoadout, levelingBuild);

    return LEVELING_EXPORT_STRING_PATERN:format(loadoutString, levelingExportStream:GetExportString());
end

--- @param deserialized table<number, TLM_DeserializedLoadout> # [nodeID] = deserializedNode
--- @param treeID number
--- @param classID number
--- @param specID number
--- @return table<number, TLM_DeserializedLoadout> # [nodeID] = deserializedNode; cleaned up node info
--- @private
function ImportExport:WriteLoadoutContent(exportStream, deserialized, treeID, classID, specID)
    --- @type TalentLoadoutManager
    local TLM = ns.TLM;
    local treeNodes = GetTreeNodes(treeID);

    local deserializedByNodeID = {};
    -- clean up the node info, in case the nodeID/entryID has changed
    for _, info in pairs(deserialized) do
        local nodeInfoExists = false;
        local nodeInfo = LibTT:GetNodeInfo(info.nodeID)
        if nodeInfo then
            for _, entryID in pairs(nodeInfo.entryIDs) do
                if entryID == info.entryID then
                    nodeInfoExists = true;
                    break;
                else
                    local entryInfo = LibTT:GetEntryInfo(entryID);
                    local definitionInfo = entryInfo and entryInfo.definitionID and C_Traits.GetDefinitionInfo(entryInfo.definitionID);
                    if definitionInfo and definitionInfo.spellID == info.spellID then
                        nodeInfoExists = true;
                        info.entryID = entryID;
                        break;
                    end
                end
            end
        end

        local nodeID, entryID = info.nodeID, info.entryID;
        if not nodeInfoExists then
            ---@diagnostic disable-next-line: cast-local-type
            nodeID, entryID = TLM:GetNodeAndEntryBySpellID(info.spellID, classID, specID);
        end
        if nodeID then
            info.entryID = entryID or info.entryID;
            deserializedByNodeID[nodeID] = info;
        end
    end

    for _, nodeID in pairs(treeNodes) do
        local isNodeGranted = LibTT:IsNodeGrantedForSpec(specID, nodeID);
        --- @type TLM_DeserializedLoadout
        local info = deserializedByNodeID[nodeID];
        exportStream:AddValue(1, (info or isNodeGranted) and 1 or 0);
        if info or isNodeGranted then -- granted or purchased
            exportStream:AddValue(1, info and 1 or 0); -- isPurchased
        end
        if info then
            local nodeInfo = LibTT:GetNodeInfo(nodeID);
            local isPartiallyRanked = nodeInfo and nodeInfo.maxRanks ~= info.rank
            exportStream:AddValue(1, isPartiallyRanked and 1 or 0);
            if isPartiallyRanked then
                exportStream:AddValue(BIT_WIDTH_RANKS_PURCHASED, info.rank);
            end

            local isChoiceNode = nodeInfo and (nodeInfo.type == Enum.TraitNodeType.Selection or nodeInfo.type == Enum.TraitNodeType.SubTreeSelection);
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

    return deserializedByNodeID;
end

--- @param treeID number
--- @param deserialized table<number, TLM_DeserializedLoadout> # [nodeID] = deserializedNode
--- @param levelingBuild TLM_LevelingBuildEntry_withLevel[]
--- @private
function ImportExport:WriteLevelingBuildContent(exportStream, treeID, deserialized, levelingBuild)
    local levelingMap = {};
    local keyFormat = '%d_%d';
    for _, entry in pairs(levelingBuild) do
        local key = keyFormat:format(entry.nodeID, entry.targetRank);
        levelingMap[key] = entry.level;
    end

    local treeNodes = GetTreeNodes(treeID);
    for _, nodeID in ipairs(treeNodes) do
        local info = deserialized[nodeID];
        if info and info.rank > 0 then
            local nodeInfo = LibTT:GetNodeInfo(nodeID);
            if nodeInfo.isSubTreeSelection then
                exportStream:AddValue(LEVELING_BIT_WIDTH_DATA, HERO_SELECTION_NODE_LEVEL);
            else
                for rank = 1, info.rank do
                    local key = keyFormat:format(nodeID, rank);
                    exportStream:AddValue(LEVELING_BIT_WIDTH_DATA, levelingMap[key] or 0);
                end
            end
        end
    end
end

