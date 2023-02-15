-----------------------------------------------------------------------------------------------
---
--- Addon developers are free to use this API to interact with TLM.
---
--- TalentLoadoutManagerAPI implements CallbackRegistryMixin, so you can register for events.
---
------------------------------------------------------------------------------------------------

local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;

--- @class TalentLoadoutManagerAPI
TalentLoadoutManagerAPI = {};

local API = TalentLoadoutManagerAPI;

API.Event = {
    --- payload: classID<number>, specID<number>, loadoutID<string>, loadoutInfo<TalentLoadoutManagerAPI_LoadoutInfo>
    CustomLoadoutApplied = TLM.Event.CustomLoadoutApplied,
    --- payload: classID<number>, specID<number>, loadoutID<number|string>, loadoutInfo<TalentLoadoutManagerAPI_LoadoutInfo>
    ---     - loadoutID is either configID or customLoadoutID
    LoadoutUpdated = TLM.Event.LoadoutUpdated,
    --- payload: <none>
    ---     - fired when the list of loadouts is updated, either due to active loadout changing,
    ---       or a loadout being created/deleted/edited
    LoadoutListUpdated = TLM.Event.LoadoutListUpdated,
};

--- @alias TalentLoadoutManagerAPI_LoadoutInfo
--- @field id number|string - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts
--- @field displayName string - blizzard loadouts are prefixed with a small Blizzard texture icon
--- @field name string - the raw loadout name
--- @field serializedNodes string - serialized loadout, this is NOT an export string, but rather an internal TLM format
--- @field owner string|nil - player-realm, only applies to Blizzard loadouts
--- @field playerIsOwner boolean - false for Blizzard loadouts owned by alts
--- @field isBlizzardLoadout boolean
--- @field classID number
--- @field specID number

--- @param displayInfo TalentLoadoutManager_LoadoutDisplayInfo
--- @return TalentLoadoutManagerAPI_LoadoutInfo
local function CreateLoadoutInfoFromDisplayInfo(displayInfo)
    return {
        id = displayInfo.id,
        displayName = displayInfo.displayName,
        name = displayInfo.loadoutInfo.name,
        serializedNodes = displayInfo.loadoutInfo.selectedNodes,
        owner = displayInfo.owner,
        playerIsOwner = displayInfo.playerIsOwner,
        isBlizzardLoadout = displayInfo.isBlizzardLoadout,
        classID = displayInfo.classID,
        specID = displayInfo.specID,
    };
end

local function IsLoadoutIDCustomLoadout(loadoutID)
    -- custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts
    return type(loadoutID) == "string" and loadoutID:sub(1, 2) == "C_";
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    Mixin(API, CallbackRegistryMixin);
    CallbackRegistryMixin.OnLoad(API);

    TLM:RegisterCallback(TLM.Event.CustomLoadoutApplied, function(self, classID, specID, loadoutID, displayInfo)
        self:TriggerEvent(self.Event.CustomLoadoutApplied, classID, specID, loadoutID, CreateLoadoutInfoFromDisplayInfo(displayInfo));
    end, API);
    TLM:RegisterCallback(TLM.Event.LoadoutUpdated, function(self, classID, specID, loadoutID, displayInfo)
        self:TriggerEvent(self.Event.LoadoutUpdated, classID, specID, loadoutID, CreateLoadoutInfoFromDisplayInfo(displayInfo));
    end, API);
    TLM:RegisterCallback(TLM.Event.LoadoutListUpdated, function(self)
        self:TriggerEvent(self.Event.LoadoutListUpdated);
    end, API);
end);


-------------------------------------------------------------------------
---
--- class and spec agnostic functions
---
--- each function has a classIDOrNil and specIDOrNil parameter,
--- if these are nil, the player's current class and spec will be used
---
-------------------------------------------------------------------------

--- @param specIDOrNil number|nil - if nil, will assume the player's current spec
--- @param classIDOrNil number|nil - if nil, will assume the player's current class
--- @return TalentLoadoutManagerAPI_LoadoutInfo[]
function API:GetLoadouts(specIDOrNil, classIDOrNil)
    local loadouts = {};
    local tlmLoadouts = TLM:GetLoadouts(classIDOrNil, specIDOrNil);

    for _, displayInfo in ipairs(tlmLoadouts) do
        table.insert(loadouts, CreateLoadoutInfoFromDisplayInfo(displayInfo));
    end

    return loadouts;
end

--- @param specIDOrNil number|nil - if nil, will assume the player's current spec
--- @param classIDOrNil number|nil - if nil, will assume the player's current class
--- @return table<number|string> - list of loadout IDs
function API:GetLoadoutIDs(specIDOrNil, classIDOrNil)
    local loadoutIDs = {};
    local tlmLoadouts = TLM:GetLoadouts(classIDOrNil, specIDOrNil);

    for _, displayInfo in ipairs(tlmLoadouts) do
        table.insert(loadoutIDs, displayInfo.id);
    end

    return loadoutIDs;
end

function API:GetAllLoadouts()
    local loadouts = {};
    local tlmLoadouts = TLM:GetAllLoadouts();

    for _, displayInfo in ipairs(tlmLoadouts) do
        table.insert(loadouts, CreateLoadoutInfoFromDisplayInfo(displayInfo));
    end

    return loadouts;
end

--- @param loadoutID number|string - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
--- @return TalentLoadoutManagerAPI_LoadoutInfo|nil
function API:GetLoadoutInfoByID(loadoutID)
    local displayInfo = TLM:GetLoadoutByID(loadoutID);

    return displayInfo and CreateLoadoutInfoFromDisplayInfo(displayInfo);
end

--- @param loadoutID number|string - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
function API:GetExportString(loadoutID)
    local displayInfo = TLM:GetLoadoutByID(loadoutID);

    return TLM:ExportLoadoutToString(displayInfo.classID, displayInfo.specID, displayInfo.loadoutInfo);
end

--- you cannot rename a Blizzard loadout if you are not the owner
--- @param loadoutID number|string - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
--- @param newName string
--- @return boolean - true if the rename was successful
function API:RenameLoadout(loadoutID, newName)
    if IsLoadoutIDCustomLoadout(loadoutID) then
        local displayInfo = TLM:GetLoadoutByID(loadoutID);
        if not displayInfo then
            return false;
        end

        return TLM:RenameCustomLoadout(displayInfo.classID, displayInfo.specID, loadoutID, newName);
    else
        return TLM:RenameBlizzardLoadout(loadoutID, newName);
    end
end

--- you cannot delete a Blizzard loadout if you are not the owner
--- @param loadoutID number|string - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
--- @return boolean - true if the delete was successful
function API:DeleteLoadout(loadoutID)
    if IsLoadoutIDCustomLoadout(loadoutID) then
        local displayInfo = TLM:GetLoadoutByID(loadoutID);
        if not displayInfo then
            return false;
        end

        return TLM:DeleteCustomLoadout(displayInfo.classID, displayInfo.specID, loadoutID);
    else
        return TLM:DeleteBlizzardLoadout(loadoutID);
    end
end

function API:ImportCustomLoadout(importText, loadoutName, autoApply)
    local newLoadoutInfo, errorOrNil = TLM:CreateCustomLoadoutFromImportString(importText, autoApply, loadoutName);

    return newLoadoutInfo and self:GetLoadoutInfoByID(newLoadoutInfo.id), errorOrNil;
end

-------------------------------------------------------------------------
---
--- character specific functions
---
--- some of these functions will directly modify the player's talents
---
-------------------------------------------------------------------------

function API:GetActiveLoadoutInfo()
    local loadoutID = self:GetActiveLoadoutID();

    return loadoutID and self:GetLoadoutInfoByID(loadoutID);
end

--- @return number|string|nil - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
function API:GetActiveLoadoutID()
    TLM:GetActiveLoadoutID()
end

--- @return number|nil - whichever loadout is selected, or the "default loadout", or nil
function API:GetActiveBlizzardLoadoutConfigID()
    TLM:GetActiveBlizzardLoadoutConfigID();
end

function API:LoadLoadout(loadoutID, autoApply)
    local displayInfo = TLM:GetLoadoutByID(loadoutID);
    if not displayInfo then
        return false;
    end

    if displayInfo.playerIsOwner and displayInfo.isBlizzardLoadout then
        -- autoApply is not supported for blizzard loadouts (yet)
        return TLM:ApplyBlizzardLoadout(displayInfo.id);
    end

    local loadoutInfo = displayInfo.loadoutInfo;
    if displayInfo.isBlizzardLoadout then
        loadoutInfo = TLM:CreateCustomLoadoutFromLoadoutData(loadoutInfo);
    end

    return TLM:ApplyCustomLoadout(loadoutInfo, autoApply);
end

function API:UpdateCustomLoadoutWithCurrentTalents(loadoutID)
    local selectedNodes = TLM:SerializeLoadout(C_ClassTalents.GetActiveConfigID());
    TLM:UpdateCustomLoadout(loadoutID, selectedNodes);
end
