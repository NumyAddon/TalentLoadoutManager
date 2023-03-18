local _, ns = ...

--- @class TalentLoadoutManager_ImportExport
local ImportExport = {};
ns.ImportExport = ImportExport;

ImportExport.bitWidthHeaderVersion = 8;
ImportExport.bitWidthSpecID = 16;
ImportExport.bitWidthRanksPurchased = 6;

--- @type LibTalentTree
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

local specToClassMap = {
    [71] = 1, [72] = 1, [73] = 1, [1446] = 1,
    [65] = 2, [66] = 2, [70] = 2, [1451] = 2,
    [253] = 3, [254] = 3, [255] = 3, [1448] = 3,
    [259] = 4, [260] = 4, [261] = 4, [1453] = 4,
    [256] = 5, [257] = 5, [258] = 5, [1452] = 5,
    [250] = 6, [251] = 6, [252] = 6, [1455] = 6,
    [262] = 7, [263] = 7, [264] = 7, [1444] = 7,
    [62] = 8, [63] = 8, [64] = 8, [1449] = 8,
    [265] = 9, [266] = 9, [267] = 9, [1454] = 9,
    [268] = 10, [270] = 10, [269] = 10, [1450] = 10,
    [102] = 11, [103] = 11, [104] = 11, [105] = 11, [1447] = 11,
    [577] = 12, [581] = 12, [1456] = 12,
    [1467] = 13, [1468] = 13, [1465] = 13,
};

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

    return serialized, nil, classIDFromString, specIDFromString;
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


function ImportExport:ExportLoadoutToString(classIDOrNil, specIDOrNil, deserializedLoadout)
    local LOADOUT_SERIALIZATION_VERSION = C_Traits.GetLoadoutSerializationVersion and C_Traits.GetLoadoutSerializationVersion() or 1;

    local classID = tonumber(classIDOrNil);
    local specID = tonumber(specIDOrNil);

    local exportStream = ExportUtil.MakeExportDataStream();
    local treeID = LibTT:GetClassTreeId(classID);

    -- write header
    exportStream:AddValue(self.bitWidthHeaderVersion, LOADOUT_SERIALIZATION_VERSION);
    exportStream:AddValue(self.bitWidthSpecID, specID);
    -- treeHash is a 128bit hash, passed as an array of 16, 8-bit values
    -- empty tree hash will disable validation on import
    exportStream:AddValue(8 * 16, 0);

    self:WriteLoadoutContent(exportStream, deserializedLoadout, treeID, classID, specID);

    return exportStream:GetExportString();
end

function ImportExport:WriteLoadoutContent(exportStream, deserialized, treeID, classID, specID)
    --- @type TalentLoadoutManager
    local TLM = ns.TLM;
    local treeNodes = GetTreeNodes(treeID);

    local deserializedByNodeID = {};
    for _, info in pairs(deserialized) do
        local nodeID, _ = TLM:GetNodeAndEntryBySpellID(info.spellID, classID, specID);
        if nodeID then
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

