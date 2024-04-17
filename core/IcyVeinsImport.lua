local name, ns = ...

--- @class TalentLoadoutManager_IcyVeinsImport
local IcyVeinsImport = {};
ns.IcyVeinsImport = IcyVeinsImport;

local skillMappings = tInvert{'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'Ă', 'ă', 'Â', 'â', 'Î', 'î', 'Ș', 'ș', 'Ț', 'ț', 'ë', 'é', 'ê', 'ï', 'ô', 'β', 'Γ', 'γ', 'Δ', 'δ', 'ε', 'ζ'};

--- @type LibTalentTree-1.0
local LibTT = LibStub('LibTalentTree-1.0');

--- @param text string
--- @return boolean
function IcyVeinsImport:IsTalentUrl(text)
    -- example URL https://www.icy-veins.com/wow/dragonflight-talent-calculator#6--250$foo+bar*
    return not not text:match('^https?://www%.icy%-veins%.com/wow/dragonflight%-talent%-calculator%#%d+%-%-%d+%$[^+]-%+[^*]-%*');
end

--- @param fullUrl string
--- @param expectedClassID number|nil # if classID from the fullUrl does not match this, the import will fail
--- @param expectedSpecID number|nil # if specID from the fullUrl does not match this, the import will fail
--- @return string|false # false on failure, serializedSelectedNodes on success
--- @return string|nil # error message on failure, serializedLevelingOrder (if any) on success
--- @return number|nil # actual classID on success
--- @return number|nil # actual specID on success
function IcyVeinsImport:BuildSerializedSelectedNodesFromUrl(fullUrl, expectedClassID, expectedSpecID)
    if not self:IsTalentUrl(fullUrl) then
        return false, 'Invalid URL';
    end

    local classID, specID, levelingOrder = self:ParseUrl(fullUrl);
    if not levelingOrder or not classID or not specID then
        return false, 'Invalid URL';
    end

    if(expectedSpecID and specID ~= expectedSpecID) then
        return false, LOADOUT_ERROR_WRONG_SPEC;
    end

    if(expectedClassID and classID ~= expectedClassID) then
        return false, 'Wrong class';
    end

    local selectedNodesByID = {};
    local serializedLevelingOrder = '';

    --- format: level_nodeID_targetRank
    local vSep = ns.SERIALIZATION_VALUE_SEPARATOR;
    local nSep = ns.SERIALIZATION_NODE_SEPARATOR;
    local lvlingFormatString = '%d' .. vSep .. '%d' .. vSep .. '%d' .. nSep;

    for level = 10, ns.MAX_LEVEL do
        local entry = levelingOrder[level];
        if entry then
            serializedLevelingOrder = serializedLevelingOrder .. string.format(
                lvlingFormatString,
                level,
                entry.nodeID,
                entry.targetRank
            );
            local nodeInfo = LibTT:GetNodeInfo(entry.nodeID);
            local entryID = entry.entryID or nodeInfo.entryIDs[1];

            local entryInfo = LibTT:GetEntryInfo(entryID);
            if entryInfo and entryInfo.definitionID then
                local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID);
                if definitionInfo.spellID then
                    local currentRank = selectedNodesByID[entry.nodeID] and selectedNodesByID[entry.nodeID].rank or 0;
                    selectedNodesByID[entry.nodeID] = {
                        nodeID = entry.nodeID,
                        entryID = entry.entryID,
                        spellID = definitionInfo.spellID,
                        rank = math.max(entry.targetRank, currentRank),
                    };
                end
            end
        end
    end

    local serializedSelectedNodes = '';
    --- format: nodeID_entryID_spellID_rank
    local formatString = "%d" .. vSep .. "%d" .. vSep .. "%d" .. vSep .. "%d" .. nSep;
    for _, info in pairs(selectedNodesByID) do
        serializedSelectedNodes = serializedSelectedNodes .. string.format(
            formatString,
            info.nodeID,
            info.entryID,
            info.spellID,
            info.rank
        );
    end

    return serializedSelectedNodes, serializedLevelingOrder, classID, specID;
end

--- @param url string
--- @return nil|number # classID
--- @return nil|number # specID
--- @return nil|table<number, TalentLoadoutManager_LevelingBuildEntry> # [level] = entry
function IcyVeinsImport:ParseUrl(url)
    local dataSection = url:match('#(.*)');

    local classID, specID, classData, specData = dataSection:match('^(%d+)%-%-(%d+)%$([^+]-)%+([^*]-)%*');
    classID = tonumber(classID);
    specID = tonumber(specID);

    local treeID = classID and LibTT:GetClassTreeId(classID);

    if not classID or not specID or not classData or not specData then
        return nil;
    end

    local classNodes, specNodes = self:GetClassAndSpecNodeIDs(specID, treeID);

    local levelingOrder = {};
    self:ParseDataSegment(8, classData, levelingOrder, classNodes);
    self:ParseDataSegment(9, specData, levelingOrder, specNodes);

    return classID, specID, levelingOrder;
end

function IcyVeinsImport:ParseDataSegment(startingLevel, dataSegment, levelingOrder, nodes)
    local splitDataSegment = {};
    for char in string.gmatch(dataSegment, '.') do
        table.insert(splitDataSegment, char);
    end
    local level = startingLevel;
    local rankByNodeID = {};
    for index, char in ipairs(splitDataSegment) do
        if char ~= '0' and char ~= '1' then
            level = level + 2;
            local nextChar = splitDataSegment[index + 1];
            local mappingIndex = skillMappings[char];

            local nodeID = nodes[mappingIndex];
            if not nodeID then
                print('Error while importing IcyVeins URL: Could not find node for mapping index', mappingIndex);
                if DevTool and DevTool.AddData then
                    DevTool:AddData({
                        mappingIndex = mappingIndex,
                        char = char,
                        nextChar = nextChar,
                        index = index,
                        dataSegment = dataSegment,
                        splitDataSegment = splitDataSegment,
                        nodes = nodes,
                    }, 'Error while importing IcyVeins URL: Could not find node for mapping index')
                end
            else
                local entryIndex = nextChar == '1' and 2 or 1;
                local nodeInfo = LibTT:GetNodeInfo(nodeID);
                local entry = nodeInfo.type == Enum.TraitNodeType.Selection and nodeInfo.entryIDs and nodeInfo.entryIDs[entryIndex] or nil;
                rankByNodeID[nodeID] = (rankByNodeID[nodeID] or 0) + 1;

                levelingOrder[level] = {
                    nodeID = nodeID,
                    entryID = entry,
                    targetRank = rankByNodeID[nodeID],
                };
            end
        end
    end
end

IcyVeinsImport.classAndSpecNodeCache = {};
function IcyVeinsImport:GetClassAndSpecNodeIDs(specID, treeID)
    if self.classAndSpecNodeCache[specID] then
        return unpack(self.classAndSpecNodeCache[specID]);
    end

    local nodes = C_Traits.GetTreeNodes(treeID);

    local classNodes = {};
    local specNodes = {};

    for _, nodeID in ipairs(nodes or {}) do
        local nodeInfo = LibTT:GetNodeInfo(nodeID);
        if LibTT:IsNodeVisibleForSpec(specID, nodeID) and nodeInfo.maxRanks > 0 then
            if nodeInfo.isClassNode then
                table.insert(classNodes, nodeID);
            else
                table.insert(specNodes, nodeID);
            end
        end
    end

    table.sort(classNodes);
    table.sort(specNodes);

    self.classAndSpecNodeCache[specID] = {classNodes, specNodes};

    return classNodes, specNodes;
end

