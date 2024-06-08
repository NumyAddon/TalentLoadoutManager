local _, ns = ...

--- @class TalentLoadoutManager_ImportExport
local ImportExport = {};
ns.ImportExport = ImportExport;

local LEVELING_BUILD_SERIALIZATION_VERSION = 1;
local LEVELING_EXPORT_STRING_PATERN = "%s-LVL-%s";

ImportExport.levelingBitWidthVersion = 5;
ImportExport.levelingBitWidthData = 7; -- allows for 128 order indexes

ImportExport.bitWidthHeaderVersion = 8;
ImportExport.bitWidthSpecID = 16;
ImportExport.bitWidthRanksPurchased = 6;

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
function ImportExport:BuildSerializedSelectedNodesFromImportString(importText, expectedClassID, expectedSpecID)
    local LOADOUT_SERIALIZATION_VERSION = C_Traits.GetLoadoutSerializationVersion and C_Traits.GetLoadoutSerializationVersion() or 1;
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

    local treeID = LibTT:GetClassTreeId(classIDFromString);
    if not self:IsHashValid(treeHash, treeID) then
        return false, LOADOUT_ERROR_TREE_CHANGED;
    end

    local loadoutContent = self:ReadLoadoutContent(importStream, treeID);

    local serialized = "";
    --- format: nodeID_entryID_spellID_rank
    local vSep = ns.SERIALIZATION_VALUE_SEPARATOR;
    local nSep = ns.SERIALIZATION_NODE_SEPARATOR;
    local formatString = "%d" .. vSep .. "%d" .. vSep .. "%d" .. vSep .. "%d" .. nSep;

    local nodes = GetTreeNodes(treeID);
    for i, nodeID in pairs(nodes) do
        local indexInfo = loadoutContent[i];
        if indexInfo.isNodeSelected then
            local nodeInfo = LibTT:GetNodeInfo(treeID, nodeID);
            local entryID = indexInfo.isChoiceNode and nodeInfo.entryIDs[indexInfo.choiceNodeSelection] or nodeInfo.entryIDs[1];
            local entryInfo = LibTT:GetEntryInfo(treeID, entryID);
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

    local serializedLevelingOrder = nil;
    local _, _, talentBuild, levelingBuild = importText:find(LEVELING_EXPORT_STRING_PATERN:format("(.*)", "(.*)"):gsub("%-", "%%-"));
    if levelingBuild then
        local levelingImportStream = ExportUtil.MakeImportDataStream(levelingBuild);
        local levelingHeaderValid, levelingSerializationVersion = self:ReadLevelingExportHeader(levelingImportStream);
        if levelingHeaderValid and levelingSerializationVersion == LEVELING_BUILD_SERIALIZATION_VERSION then
            local loadoutEntryInfo = self:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent);
            local levelingBuildEntries = self:ReadLevelingBuildContent(levelingImportStream, loadoutEntryInfo);

            serializedLevelingOrder = "";
            --- format: level_nodeID_targetRank
            local lvlingFormatString = "%d" .. vSep .. "%d" .. vSep .. "%d" .. nSep;
            for level = 10, ns.MAX_LEVEL do
                local entry = levelingBuildEntries[level];
                if entry then
                    serializedLevelingOrder = serializedLevelingOrder .. string.format(
                        lvlingFormatString,
                        level,
                        entry.nodeID,
                        entry.targetRank
                    );
                end
            end
        end
    end

    return serialized, serializedLevelingOrder, classIDFromString, specIDFromString;
end

function ImportExport:ReadLoadoutHeader(importStream)
    local headerBitWidth = self.bitWidthHeaderVersion + self.bitWidthSpecID + 128;
    local importStreamTotalBits = importStream:GetNumberOfBits();
    if( importStreamTotalBits < headerBitWidth) then
        return false, 0, 0, 0;
    end
    local serializationVersion = importStream:ExtractValue(self.bitWidthHeaderVersion);
    local specID = importStream:ExtractValue(self.bitWidthSpecID);

    -- treeHash is a 128bit hash, passed as an array of 16, 8-bit values
    local treeHash = {};
    for i=1,16,1 do
        treeHash[i] = importStream:ExtractValue(8);
    end
    return true, serializationVersion, specID, treeHash;
end

function ImportExport:ReadLevelingExportHeader(importStream)
    local headerBitWidth = self.levelingBitWidthVersion;
    local importStreamTotalBits = importStream:GetNumberOfBits();
    if( importStreamTotalBits < headerBitWidth) then
        return false, 0;
    end
    local serializationVersion = importStream:ExtractValue(self.levelingBitWidthVersion);

    return true, serializationVersion;
end

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


function ImportExport:ReadLoadoutContent(importStream, treeID)
    local results = {};

    local treeNodes = GetTreeNodes(treeID);
    for i, _ in ipairs(treeNodes) do
        local nodeSelectedValue = importStream:ExtractValue(1)
        local isNodeSelected =  nodeSelectedValue == 1;
        local isPartiallyRanked = false;
        local partialRanksPurchased = 0;
        local isChoiceNode = false;
        local choiceNodeSelection = 0;

        if(isNodeSelected) then
            local isPartiallyRankedValue = importStream:ExtractValue(1);
            isPartiallyRanked = isPartiallyRankedValue == 1;
            if(isPartiallyRanked) then
                partialRanksPurchased = importStream:ExtractValue(self.bitWidthRanksPurchased);
            end
            local isChoiceNodeValue = importStream:ExtractValue(1);
            isChoiceNode = isChoiceNodeValue == 1;
            if(isChoiceNode) then
                choiceNodeSelection = importStream:ExtractValue(2);
            end
        end

        local result = {};
        result.isNodeSelected = isNodeSelected;
        result.isPartiallyRanked = isPartiallyRanked;
        result.partialRanksPurchased = partialRanksPurchased;
        result.isChoiceNode = isChoiceNode;
        -- entry index is stored as zero-index, so convert back to lua index
        result.choiceNodeSelection = choiceNodeSelection + 1;
        results[i] = result;
    end

    return results;
end

--- @param loadoutEntryInfo TalentLoadoutManager_LoadoutEntryInfo[]
--- @return table<number, TalentLoadoutManager_LevelingBuildEntry> # [level] = entry
function ImportExport:ReadLevelingBuildContent(importStream, loadoutEntryInfo)
    local results = {};

    local purchasesByNodeID = {};
    for level = 10, ns.MAX_LEVEL + 1 do
        local success, orderIndex = pcall(importStream.ExtractValue, importStream, 7);
        if not success or not orderIndex then break; end -- end of stream

        local entry = loadoutEntryInfo[orderIndex];
        if entry then
            purchasesByNodeID[entry.nodeID] = entry.ranksPurchased;
            local result = {};
            result.nodeID = entry.nodeID;
            results[level] = result;
        end
    end
    for level = ns.MAX_LEVEL, 9, -1 do
        local result = results[level];
        if result then
            result.targetRank = purchasesByNodeID[result.nodeID];
            purchasesByNodeID[result.nodeID] = purchasesByNodeID[result.nodeID] - 1;
        end
    end

    return results;
end

--- converts from compact bit-packing format to LoadoutEntryInfo format to pass to ImportLoadout API
--- @return TalentLoadoutManager_LoadoutEntryInfo[]
function ImportExport:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent)
    local results = {};
    local treeNodes = C_Traits.GetTreeNodes(treeID);
    local count = 1;
    for i, treeNodeID in ipairs(treeNodes) do

        local indexInfo = loadoutContent[i];

        if (indexInfo.isNodeSelected) then
            local treeNode = LibTT:GetNodeInfo(treeNodeID);
            local isChoiceNode = treeNode.type == Enum.TraitNodeType.Selection or treeNode.type == Enum.TraitNodeType.SubTreeSelection;
            local choiceNodeSelection = indexInfo.isChoiceNode and indexInfo.choiceNodeSelection or nil;
            if indexInfo.isNodeSelected and isChoiceNode ~= indexInfo.isChoiceNode then
                -- guard against corrupt import strings
                print(string.format('Import string is corrupt, node type mismatch at nodeID %d. First option will be selected.', treeNodeID));
                choiceNodeSelection = 1;
            end
            --- @type TalentLoadoutManager_LoadoutEntryInfo
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

function ImportExport:TryExportBlizzardLoadoutToString(configID, specID)
    local loadoutString = C_Traits.GenerateImportString(configID);
    if not loadoutString or '' == loadoutString then
        return nil;
    end

    local exportStream = ExportUtil.MakeExportDataStream();
    local importStream = ExportUtil.MakeImportDataStream(loadoutString);

    if importStream:ExtractValue(self.bitWidthHeaderVersion) ~= 1 then
        return nil; -- only version 1 is supported
    end

    local headerSpecID = importStream:ExtractValue(self.bitWidthSpecID);
    if headerSpecID == specID then
        return loadoutString; -- no update needed
    end

    exportStream:AddValue(self.bitWidthHeaderVersion, 1);
    exportStream:AddValue(self.bitWidthSpecID, specID);
    local remainingBits = importStream:GetNumberOfBits() - self.bitWidthHeaderVersion - self.bitWidthSpecID;
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
--- @param deserializedLoadout table<number, TalentLoadoutManager_DeserializedLoadout> [nodeID] = deserializedNode
--- @param levelingBuild nil|table<number, TalentLoadoutManager_LevelingBuildEntry> # [level] = entry
function ImportExport:ExportLoadoutToString(classID, specID, deserializedLoadout, levelingBuild)
    local LOADOUT_SERIALIZATION_VERSION = C_Traits.GetLoadoutSerializationVersion and C_Traits.GetLoadoutSerializationVersion() or 1;

    local exportStream = ExportUtil.MakeExportDataStream();
    local treeID = LibTT:GetClassTreeId(classID);

    -- write header
    exportStream:AddValue(self.bitWidthHeaderVersion, LOADOUT_SERIALIZATION_VERSION);
    exportStream:AddValue(self.bitWidthSpecID, specID);
    -- treeHash is a 128bit hash, passed as an array of 16, 8-bit values
    -- empty tree hash will disable validation on import
    exportStream:AddValue(8 * 16, 0);

    local cleanedDeserializedLoadout = self:WriteLoadoutContent(exportStream, deserializedLoadout, treeID, classID, specID);

    local loadoutString = exportStream:GetExportString();
    if not levelingBuild or not next(levelingBuild) then
        return loadoutString
    end

    local levelingExportStream = ExportUtil.MakeExportDataStream();
    levelingExportStream:AddValue(self.levelingBitWidthVersion, LEVELING_BUILD_SERIALIZATION_VERSION);
    self:WriteLevelingBuildContent(levelingExportStream, treeID, cleanedDeserializedLoadout, levelingBuild);

    return LEVELING_EXPORT_STRING_PATERN:format(loadoutString, levelingExportStream:GetExportString());
end

--- @param deserialized table<number, TalentLoadoutManager_DeserializedLoadout> # [nodeID] = deserializedNode
--- @param treeID number
--- @param classID number
--- @param specID number
--- @return table<number, TalentLoadoutManager_DeserializedLoadout> # [nodeID] = deserializedNode; cleaned up node info
function ImportExport:WriteLoadoutContent(exportStream, deserialized, treeID, classID, specID)
    --- @type TalentLoadoutManager
    local TLM = ns.TLM;
    local treeNodes = GetTreeNodes(treeID);

    local deserializedByNodeID = {};
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
            nodeID, entryID = TLM:GetNodeAndEntryBySpellID(info.spellID, classID, specID);
        end
        if nodeID then
            info.entryID = entryID or info.entryID;
            deserializedByNodeID[nodeID] = info;
        end
    end

    for _, nodeID in pairs(treeNodes) do
        local info = deserializedByNodeID[nodeID];
        exportStream:AddValue(1, info and 1 or 0);
        if info then
            local nodeInfo = LibTT:GetNodeInfo(treeID, nodeID);
            local isPartiallyRanked = nodeInfo and nodeInfo.maxRanks ~= info.rank
            exportStream:AddValue(1, isPartiallyRanked and 1 or 0);
            if isPartiallyRanked then
                exportStream:AddValue(self.bitWidthRanksPurchased, info.rank);
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
--- @param deserialized table<number, TalentLoadoutManager_DeserializedLoadout> # [nodeID] = deserializedNode
--- @param levelingBuild table<number, TalentLoadoutManager_LevelingBuildEntry> # [level] = entry
function ImportExport:WriteLevelingBuildContent(exportStream, treeID, deserialized, levelingBuild)
    local purchasedNodesOrder = {};
    local treeNodes = GetTreeNodes(treeID);
    local i = 0;
    for _, nodeID in ipairs(treeNodes) do
        local info = deserialized[nodeID];
        if info and info.rank > 0 then
            i = i + 1;
            purchasedNodesOrder[nodeID] = i;
        end
    end
    local numberOfLevelingEntries = 0;
    for level = 10, ns.MAX_LEVEL do
        local entry = levelingBuild[level];
        if entry then
            numberOfLevelingEntries = numberOfLevelingEntries + 1;
        end
    end

    for level = 10, ns.MAX_LEVEL do
        local entry = levelingBuild[level];
        exportStream:AddValue(7, entry and purchasedNodesOrder[entry.nodeID] or 0);
        numberOfLevelingEntries = numberOfLevelingEntries - (entry and 1 or 0);
        if 0 == numberOfLevelingEntries then
            break;
        end
    end
end

