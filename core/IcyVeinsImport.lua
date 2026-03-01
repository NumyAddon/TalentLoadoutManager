local name, ns = ...

--- @class TLM_IcyVeinsImport
local IcyVeinsImport = {};
ns.IcyVeinsImport = IcyVeinsImport;

--- @type LibTalentTree-1.0
local LibTT = LibStub('LibTalentTree-1.0');

local HERO_SELECTION_NODE_LEVEL = 71;

IcyVeinsImport.TREE_TYPE_CLASS = 'class';
IcyVeinsImport.TREE_TYPE_SPEC = 'spec';
IcyVeinsImport.TREE_TYPE_SUB_TREE = 'subTree';

IcyVeinsImport.bitWidthSpecID = 12;
IcyVeinsImport.bitWidthNodeIndex = 6;
--- @private
IcyVeinsImport.classAndSpecNodeCache = {};

local apexTalentLevels = { 81, 84, 87, 90 };

--- @param text string
--- @return boolean
--- @public
function IcyVeinsImport:IsTalentUrl(text)
    -- example URL https://www.icy-veins.com/wow/midnight-talent-calculator#seg1-seg2-seg3-seg4-seg5-seg6
    return not not text:match('^https?://www%.icy%-veins%.com/wow/midnight%-talent%-calculator%#[^-]*%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-?[^-]*$');
end

--- @param fullUrl string
--- @param expectedClassID number|nil # if set and the classID from the fullUrl does not match this, the import will fail
--- @param expectedSpecID number|nil # if set and the specID from the fullUrl does not match this, the import will fail
--- @return string|false # false on failure, serializedSelectedNodes on success
--- @return string|nil # error message on failure, serializedLevelingOrder (if any) on success
--- @return number|nil # actual classID on success
--- @return number|nil # actual specID on success
--- @public
function IcyVeinsImport:BuildSerializedSelectedNodesFromUrl(fullUrl, expectedClassID, expectedSpecID)
    if not self:IsTalentUrl(fullUrl) then
        return false, 'Invalid URL';
    end

    local classID, specID, levelingBuild = self:ParseUrl(fullUrl);
    if not levelingBuild or not classID or not specID then
        return false, 'Invalid URL';
    end

    if (expectedSpecID and specID ~= expectedSpecID) then
        return false, LOADOUT_ERROR_WRONG_SPEC;
    end

    if (expectedClassID and classID ~= expectedClassID) then
        return false, 'Wrong class';
    end

    local selectedNodesByID = {};
    local serializedLevelingOrder = '';

    local vSep = ns.SERIALIZATION_VALUE_SEPARATOR;
    local nSep = ns.SERIALIZATION_NODE_SEPARATOR;

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
            local nodeInfo = LibTT:GetNodeInfo(entry.nodeID);
            local entryID = entry.entryID or nodeInfo.entryIDs[1];

            local entryInfo = LibTT:GetEntryInfo(entryID);
            if entryInfo and entryInfo.definitionID then
                local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID);
                if definitionInfo and definitionInfo.spellID then
                    local currentRank = selectedNodesByID[entry.nodeID] and selectedNodesByID[entry.nodeID].rank or 0;
                    selectedNodesByID[entry.nodeID] = {
                        nodeID = entry.nodeID,
                        entryID = entryID,
                        spellID = definitionInfo.spellID,
                        rank = math.max(entry.targetRank, currentRank),
                    };
                end
            end
        end
    end
    if levelingBuild.selectedSubTreeID then
        local nodeID, _ = LibTT:GetSubTreeSelectionNodeIDAndEntryIDBySpecID(specID, levelingBuild.selectedSubTreeID);
        if nodeID then
            serializedLevelingOrder = serializedLevelingOrder .. string.format(
                lvlingFormatString,
                HERO_SELECTION_NODE_LEVEL,
                nodeID,
                1
            );
            selectedNodesByID[nodeID] = {
                nodeID = nodeID,
                entryID = nil,
                spellID = levelingBuild.selectedSubTreeID,
                rank = 1,
            };
        end
    end

    local serializedSelectedNodes = '';
    --- format: nodeID_entryID_spellIDOrSubTreeID_rank
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
--- @return nil|TLM_LevelingBuild
--- @private
function IcyVeinsImport:ParseUrl(url)
    local dataSection = url:match('#(.*)');
    dataSection = dataSection:gsub(':', '/'); -- IcyVeins uses base64 with `:`, whereas wow uses `/`

    local sections = { string.split('-', dataSection) };
    local sectionCount = #sections;
    local specIDString, classString, specString = sections[1], sections[2], sections[3];
    local apexTalentString = sectionCount == 6 and sections[4] or "";
    local heroString = sectionCount == 6 and sections[5] or sections[4];
    local specIDStream = ExportUtil.MakeImportDataStream(specIDString);
    local specID = tonumber(specIDStream:ExtractValue(self.bitWidthSpecID));
    local classID = specID and C_SpecializationInfo.GetClassIDFromSpecID(specID);

    local treeID = classID and LibTT:GetClassTreeID(classID);

    if not classID or not specID or not classString or not specString or not treeID then
        return nil;
    end
    local classStream = ExportUtil.MakeImportDataStream(classString);
    local specStream = ExportUtil.MakeImportDataStream(specString);
    local apexTalentStream = ExportUtil.MakeImportDataStream(apexTalentString);
    local heroStream = ExportUtil.MakeImportDataStream(heroString);
    local selectedSubTreeID;
    if heroStream:GetNumberOfBits() > 0 then
        local heroTreeIndex = heroStream:ExtractValue(1) + 1;
        selectedSubTreeID = LibTT:GetSubTreeIDsForSpecID(specID)[heroTreeIndex];
    end

    local classNodes, specNodes, apexNodes, heroNodes = self:GetClassAndSpecNodeIDs(specID, treeID, selectedSubTreeID);

    local levelingBuild = { entries = {}, selectedSubTreeID = selectedSubTreeID };
    levelingBuild.entries[1] = self:ParseDataSegment(classStream, classNodes, self.TREE_TYPE_CLASS);
    levelingBuild.entries[2] = self:ParseDataSegment(specStream, specNodes, self.TREE_TYPE_SPEC);
    local apexEntries = apexTalentString ~= "" and self:ParseDataSegment(apexTalentStream, apexNodes, self.TREE_TYPE_SPEC) or nil;
    if apexEntries and next(apexEntries) then
        local count = table.count(apexEntries);
        local nodeID = apexNodes[1];
        for _, level in ipairs_reverse(apexTalentLevels) do
            if not levelingBuild.entries[2][level] then
                levelingBuild.entries[2][level] = {
                    nodeID = nodeID,
                    targetRank = count,
                };
                count = count - 1;
                if count == 0 then break; end
            end
        end
    end
    if heroNodes and selectedSubTreeID then
        levelingBuild.entries[selectedSubTreeID] = self:ParseDataSegment(heroStream, heroNodes, self.TREE_TYPE_SUB_TREE);
    end

    return classID, specID, levelingBuild;
end

--- @param dataStream ImportDataStreamMixin
--- @param nodes number[]
--- @param treeType 'class'|'spec'|'subTree'
--- @return table<number, TLM_LevelingBuildEntry_withEntry> # [level] = entry
--- @private
function IcyVeinsImport:ParseDataSegment(dataStream, nodes, treeType)
    local rankByNodeID = {};
    local levelingOrder = {};
    local currencySpent = 0;

    while (dataStream:GetNumberOfBits() - dataStream.currentExtractedBits) > self.bitWidthNodeIndex do
        local success, nodeIndex = pcall(function() return dataStream:ExtractValue(self.bitWidthNodeIndex); end);
        if not success or not nodeIndex then break; end

        nodeIndex = nodeIndex + 1; -- 0-based to 1-based
        local nodeID = nodes[nodeIndex];
        if not nodeID then
            print('Error while importing IcyVeins URL: Could not find node for index', nodeIndex, '-', treeType);
            if DevTool and DevTool.AddData then
                DevTool:AddData({
                    nodeIndex = nodeIndex,
                    nodes = nodes,
                    treeType = treeType,
                }, 'Error while importing IcyVeins URL: Could not find node for index')
            end
        else
            local nodeInfo = LibTT:GetNodeInfo(nodeID);
            local isChoiceNode = nodeInfo.type == Enum.TraitNodeType.Selection or nodeInfo.type == Enum.TraitNodeType.SubTreeSelection;
            local entry
            if isChoiceNode then
                local choiceIndex = dataStream:ExtractValue(1) + 1;
                entry = nodeInfo.entryIDs and nodeInfo.entryIDs[choiceIndex] or nil;
            end
            rankByNodeID[nodeID] = (rankByNodeID[nodeID] or 0) + 1;
            currencySpent = currencySpent + 1;
            local level = self:GetRequiredLevelForCurrencySpent(currencySpent, treeType);

            levelingOrder[level] = {
                nodeID = nodeID,
                entryID = entry,
                targetRank = rankByNodeID[nodeID],
            };
        end
    end

    return levelingOrder;
end

--- @param spent number
--- @param treeType 'class'|'spec'|'subTree'
--- @return number requiredLevel
function IcyVeinsImport:GetRequiredLevelForCurrencySpent(spent, treeType)
    local requiredLevel;
    if self.TREE_TYPE_CLASS == treeType then
        -- starts at 8 (so that first talent point results in level 10)
        -- 10-70 = spendingUnderOrEqual31 * 2
        -- 81-90 = spendingOver31 * 3
        -- ignore apex talents for now
        if spent > 31 then
            requiredLevel = 79 + ((spent - 31) * 3);
        else
            requiredLevel = 8 + (spent * 2);
        end
    elseif self.TREE_TYPE_SUB_TREE == treeType then
        -- starts at 70 (so that first talent point results in level 71)
        -- 71-80 = spendingUnderOrEqual10 * 1
        -- 81-90 = spendingOver10 * 3
        if spent > 10 then
            requiredLevel = 80 + ((spent - 10) * 3);
        else
            requiredLevel = 70 + spent;
        end
    elseif self.TREE_TYPE_SPEC == treeType then
        -- if apex talent selected: minimum level is 80 regardless of spending
        -- starts at 9 (so that first talent point results in level 11)
        -- 11-70 = spendingUnderOrEqual30 * 2
        -- 81-90 = spendingOver30 * 3
        if spent > 30 then
            requiredLevel = 78 + ((spent - 30) * 3);
        else
            requiredLevel = 9 + (spent * 2);
        end
    else
        error('Invalid currency type: ' .. tostring(treeType));
    end

    return math.max(10, requiredLevel);
end

--- @param specID number
--- @param treeID number
--- @param selectedSubTreeID number?
--- @return number[], number[], number[], number[]|nil # classNodes, specNodes, apexNodes, heroNodes (if applicable)
--- @private
function IcyVeinsImport:GetClassAndSpecNodeIDs(specID, treeID, selectedSubTreeID)
    if self.classAndSpecNodeCache[specID] then
        local classNodes, specNodes, apexNodes, heroNodesByTree = unpack(self.classAndSpecNodeCache[specID]);

        return classNodes, specNodes, apexNodes, heroNodesByTree[selectedSubTreeID] or nil;
    end

    local nodes = C_Traits.GetTreeNodes(treeID);

    local classNodes = {};
    local specNodes = {};
    local apexNodes = {};
    local heroNodesByTree = {};

    for _, nodeID in ipairs(nodes or {}) do
        local nodeInfo = LibTT:GetNodeInfo(nodeID);
        if LibTT:IsNodeVisibleForSpec(specID, nodeID) and nodeInfo.maxRanks > 0 then
            if nodeInfo.isSubTreeSelection then
                -- skip
            elseif nodeInfo.isApexTalent then
                table.insert(apexNodes, nodeID);
            elseif nodeInfo.subTreeID then
                heroNodesByTree[nodeInfo.subTreeID] = heroNodesByTree[nodeInfo.subTreeID] or {};
                table.insert(heroNodesByTree[nodeInfo.subTreeID], nodeID);
            elseif nodeInfo.isClassNode then
                table.insert(classNodes, nodeID);
            else
                table.insert(specNodes, nodeID);
            end
        end
    end
    for _, subTreeNodes in pairs(heroNodesByTree) do
        table.sort(subTreeNodes);
    end

    table.sort(classNodes);
    table.sort(specNodes);
    table.sort(apexNodes);

    self.classAndSpecNodeCache[specID] = { classNodes, specNodes, apexNodes, heroNodesByTree };

    return classNodes, specNodes, apexNodes, heroNodesByTree[selectedSubTreeID] or nil;
end

