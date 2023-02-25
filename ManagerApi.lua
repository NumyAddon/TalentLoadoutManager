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

--- @class TalentLoadoutManagerAPI_GlobalAPI
local GlobalAPI = {};
--- @class TalentLoadoutManagerAPI_CharacterAPI
local CharacterAPI = {};
--- @type TalentLoadoutManagerAPI
local API = TalentLoadoutManagerAPI;

API.GlobalAPI = GlobalAPI;
API.CharacterAPI = CharacterAPI;
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
--- some of these functions have a classIDOrNil and specIDOrNil parameter,
--- if these are nil, the player's current class and spec will be used
---
-------------------------------------------------------------------------

--- Returns loadouts for the specified class and spec
--- @param specIDOrNil number|nil - if nil, will assume the player's current spec
--- @param classIDOrNil number|nil - if nil, will assume the player's current class
--- @return TalentLoadoutManagerAPI_LoadoutInfo[]
function GlobalAPI:GetLoadouts(specIDOrNil, classIDOrNil)
    local loadouts = {};
    local tlmLoadouts = TLM:GetLoadouts(classIDOrNil, specIDOrNil);

    for _, displayInfo in ipairs(tlmLoadouts) do
        table.insert(loadouts, CreateLoadoutInfoFromDisplayInfo(displayInfo));
    end

    return loadouts;
end

--- Returns loadout IDs for the specified class and spec
--- @param specIDOrNil number|nil - if nil, will assume the player's current spec
--- @param classIDOrNil number|nil - if nil, will assume the player's current class
--- @return table<number|string> - list of loadout IDs
function GlobalAPI:GetLoadoutIDs(specIDOrNil, classIDOrNil)
    local loadoutIDs = {};
    local tlmLoadouts = TLM:GetLoadouts(classIDOrNil, specIDOrNil);

    for _, displayInfo in ipairs(tlmLoadouts) do
        table.insert(loadoutIDs, displayInfo.id);
    end

    return loadoutIDs;
end

--- Returns loadouts for all classes and specs
--- @return TalentLoadoutManagerAPI_LoadoutInfo[]
function GlobalAPI:GetAllLoadouts()
    local loadouts = {};
    local tlmLoadouts = TLM:GetAllLoadouts();

    for _, displayInfo in ipairs(tlmLoadouts) do
        table.insert(loadouts, CreateLoadoutInfoFromDisplayInfo(displayInfo));
    end

    return loadouts;
end

--- @param loadoutID number|string - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
--- @return TalentLoadoutManagerAPI_LoadoutInfo|nil
function GlobalAPI:GetLoadoutInfoByID(loadoutID)
    local displayInfo = TLM:GetLoadoutByID(loadoutID);

    return displayInfo and CreateLoadoutInfoFromDisplayInfo(displayInfo);
end

--- @param loadoutID number|string - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
function GlobalAPI:GetExportString(loadoutID)
    local displayInfo = TLM:GetLoadoutByID(loadoutID);

    return displayInfo and TLM:ExportLoadoutToString(displayInfo.classID, displayInfo.specID, displayInfo.loadoutInfo);
end

--- you cannot rename a Blizzard loadout if you are not the owner
--- @param loadoutID number|string - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
--- @param newName string
--- @return boolean - true if the rename was successful
function GlobalAPI:RenameLoadout(loadoutID, newName)
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
function GlobalAPI:DeleteLoadout(loadoutID)
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

--- Create a new Custom Loadout from an import string
--- @param importText string - the import string
--- @param loadoutName string - the name of the new loadout
--- @return TalentLoadoutManagerAPI_LoadoutInfo|boolean, string|nil - the new loadout info, or false if there was an error; second return value is the error message if there was an error
function GlobalAPI:ImportCustomLoadout(importText, loadoutName)
    local autoApply, validateClassAndSpec, load = false, false, false;
    local newLoadoutInfo, errorOrNil = TLM:CreateCustomLoadoutFromImportString(importText, autoApply, loadoutName, validateClassAndSpec, load);

    return newLoadoutInfo and self:GetLoadoutInfoByID(newLoadoutInfo.id) or false, errorOrNil;
end

--- Update an existing Custom Loadout from an import string
--- @param loadoutID number|string - the loadout ID
--- @param importText string - the import string
--- @return TalentLoadoutManagerAPI_LoadoutInfo|boolean, string|nil - updated loadout info, if the update was successful, false if there was an error; second return value is the error message if there was an error
function GlobalAPI:UpdateCustomLoadoutWithImportString(loadoutID, importText)
    local loadoutInfo = self:GetLoadoutInfoByID(loadoutID);
    if not loadoutInfo then
        return false, "Loadout not found";
    end
    local result, errorOrNil = TLM:BuildSerializedSelectedNodesFromImportString(importText, loadoutInfo.classID, loadoutInfo.specID);
    if result then
        TLM:UpdateCustomLoadout(loadoutID, result);
    end
    return result and self:GetLoadoutInfoByID(loadoutID) or false, errorOrNil;
end

-------------------------------------------------------------------------
---
--- character specific functions
---
--- some of these functions will directly modify the player's talents
---
-------------------------------------------------------------------------

--- Get the active loadout info for the current character, this can be a Blizzard loadout, or a custom loadout, or nil if there is no active loadout
--- @return TalentLoadoutManagerAPI_LoadoutInfo|nil - the active loadout info
function CharacterAPI:GetActiveLoadoutInfo()
    local loadoutID = self:GetActiveLoadoutID();

    return loadoutID and GlobalAPI:GetLoadoutInfoByID(loadoutID);
end

--- Get the active loadout ID for the current character, this can be a Blizzard loadout, or a custom loadout, or nil if there is no active loadout
--- @return number|string|nil - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
function CharacterAPI:GetActiveLoadoutID()
    return TLM:GetActiveLoadoutID();
end

--- Get the active Blizzard loadout ConfigID for the current character, or the "default loadout" or nil if there is no active Blizzard loadout
--- @return number|nil
function CharacterAPI:GetActiveBlizzardLoadoutConfigID()
    return TLM:GetActiveBlizzardLoadoutConfigID();
end

--- Load a loadout, this will apply the loadout to the current character
--- @param loadoutID number|string - the loadout ID, this can be a blizzard ConfigID, or a custom TLM loadout ID
--- @param autoApply boolean - if true, the talent changes will be applied immediately, if false, they are left pending
function CharacterAPI:LoadLoadout(loadoutID, autoApply)
    local displayInfo = TLM:GetLoadoutByID(loadoutID);
    if not displayInfo then
        return false;
    end

    if displayInfo.playerIsOwner and displayInfo.isBlizzardLoadout then
        return TLM:ApplyBlizzardLoadout(displayInfo.id, autoApply);
    end

    local loadoutInfo = displayInfo.loadoutInfo;
    if displayInfo.isBlizzardLoadout then
        loadoutInfo = TLM:CreateCustomLoadoutFromLoadoutData(loadoutInfo);
    end

    return TLM:ApplyCustomLoadout(loadoutInfo, autoApply);
end

--- Update a custom loadout with the current talents
function CharacterAPI:UpdateCustomLoadoutWithCurrentTalents(loadoutID)
    local configID = C_ClassTalents.GetActiveConfigID();
    if not configID then return; end

    local selectedNodes = TLM:SerializeLoadout(C_ClassTalents.GetActiveConfigID());
    TLM:UpdateCustomLoadout(loadoutID, selectedNodes);
end

--- Create a new custom loadout from the current talents
--- The new loadout will be set as active automatically
--- @param loadoutName string - the name of the new loadout
--- @return TalentLoadoutManagerAPI_LoadoutInfo - the new loadout info
function CharacterAPI:CreateCustomLoadoutFromCurrentTalents(loadoutName)
    local loadoutInfo = TLM:CreateCustomLoadoutFromActiveTalents(loadoutName, nil, nil);

    return GlobalAPI:GetLoadoutInfoByID(loadoutInfo.id);
end

--- Create a new custom loadout from an import string
--- @param importText string - the import string
--- @param loadoutName string - the name of the new loadout
--- @param autoApply boolean - if true, the talent changes will be applied immediately, if false, they are left pending
--- @return TalentLoadoutManagerAPI_LoadoutInfo, string|nil - the new loadout info, second return value is the error message if there was an error
function CharacterAPI:ImportCustomLoadout(importText, loadoutName, autoApply)
    local validateClassAndSpec, load = true, true;
    local newLoadoutInfo, errorOrNil = TLM:CreateCustomLoadoutFromImportString(importText, autoApply, loadoutName, validateClassAndSpec, load);

    return newLoadoutInfo and GlobalAPI:GetLoadoutInfoByID(newLoadoutInfo.id), errorOrNil;
end
