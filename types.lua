--- @meta _
--- Only some of the types described here, are part of the public API.

-------------------
----- public ------
-------------------

--- @class TalentLoadoutManagerAPI_LoadoutInfo
--- @field id number|string - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts
--- @field displayName string - blizzard loadouts are prefixed with a small Blizzard icon, leveling builds have an XP icon prefixed
--- @field name string - the raw loadout name
--- @field serializedNodes string - serialized loadout, this is NOT an export string, but rather an internal TLM format
--- @field serializedLevelingOrder string|nil - serialized leveling order, nil if no leveling information is attached, it's also an internal TLM format
--- @field owner string|nil - player-realm, only applies to Blizzard loadouts
--- @field playerIsOwner boolean - false for Blizzard loadouts owned by alts
--- @field isBlizzardLoadout boolean
--- @field parentMapping number[]|nil - only set if this is a custom loadout, [playerName-realmName] = parentLoadoutID, position [0] contains the current player's parentLoadoutID if any
--- @field classID number
--- @field specID number
--- @field isLocked boolean - should appear locked in the UI, and should not be edited (the API won't block it though)

-------------------
----- private -----
-------------------
--- @class TLM_SideBarDataProviderEntry
--- @field text string
--- @field data TLM_SideBarLoadoutInfo
--- @field isActive boolean
--- @field parentID number|nil

--- @class TLM_SideBarLoadoutInfo: TalentLoadoutManagerAPI_LoadoutInfo
--- @field parentID number|nil

--- @class TLM_LevelingBuildEntry
--- @field nodeID number
--- @field targetRank number # for choice nodes, this is always 1

--- @class TLM_LevelingBuildEntry_withEntry: TLM_LevelingBuildEntry
--- @field entryID number|nil

--- @class TLM_LevelingBuildEntry_withLevel: TLM_LevelingBuildEntry
--- @field level number

--- @class TLM_LevelingBuild
--- @field entries table<number, table<number, TLM_LevelingBuildEntry_withEntry>> # [tree] = {[level] = entry}, where tree is 1 for class, 2 for spec, or tree is SubTreeID for hero specs
--- @field selectedSubTreeID number? # Selected Hero Spec ID, if any

--- @class TLM_LoadoutEntryInfo
--- @field nodeID number
--- @field ranksPurchased number
--- @field selectionEntryID number
--- @field isChoiceNode boolean

--- @class TLM_LoadoutDisplayInfo
--- @field id number|string  - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts
--- @field displayName string
--- @field loadoutInfo TLM_LoadoutInfo
--- @field owner string|nil
--- @field playerIsOwner boolean
--- @field isBlizzardLoadout boolean
--- @field parentMapping number[]|nil - only set if this is a custom loadout, [playerName-realmName] = parentLoadoutID, position [0] contains the current player's parentLoadoutID if any
--- @field classID number
--- @field specID number
--- @field isLocked boolean - should appear locked in the UI, and should not be edited (the API won't block it though)

--- @class TLM_LoadoutInfo_partial
--- @field name string
--- @field selectedNodes string - serialized loadout
--- @field levelingOrder string|nil - serialized leveling order
--- @field isLocked boolean - should appear locked in the UI, and should not be edited (the API won't block it though)

--- @class TLM_LoadoutInfo: TLM_LoadoutInfo_partial
--- @field id number|string - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts

--- @class TLM_DeserializedLoadout
--- @field nodeID number
--- @field entryID number
--- @field spellID number # instead contains the SubTreeID, if the node is a subtree selection node
--- @field rank number

--- @class TLM_ElementFrame: Button

--- @alias TLM_ConfigOptions
---|"autoApplyOnLevelUp"
---|"autoScale"
---|"autoPosition"
---|"autoApply"
---|"integrateWithSimc"
---|"sideBarBackgroundColor"
---|"sideBarActiveElementTextColor"
---|"sideBarActiveElementBackgroundColor"
---|"sideBarActiveElementHighlightBackgroundColor"
---|"sideBarInactiveElementTextColor"
---|"sideBarInactiveElementBackgroundColor"
---|"sideBarInactiveElementHighlightBackgroundColor"

-------------------
----- FrameXML ----
-------------------

---[FrameXML](https://www.townlong-yak.com/framexml/go/ImportDataStreamMixin)
---@class ImportDataStreamMixin
---@field dataValues number[]
---@field currentIndex number
---@field currentExtractedBits number
---@field currentRemainingValue number
ImportDataStreamMixin = {}

---[FrameXML](https://www.townlong-yak.com/framexml/go/ImportDataStreamMixin:Init)
---@param exportString string
function ImportDataStreamMixin:Init(exportString) end

---[FrameXML](https://www.townlong-yak.com/framexml/go/ImportDataStreamMixin:ExtractValue)
---@param bitWidth number
---@return number?
function ImportDataStreamMixin:ExtractValue(bitWidth) end

---[FrameXML](https://www.townlong-yak.com/framexml/go/ImportDataStreamMixin:GetNumberOfBits)
---@return number
function ImportDataStreamMixin:GetNumberOfBits() end

---[FrameXML](https://www.townlong-yak.com/framexml/go/ExportUtil.MakeImportDataStream)
---@param exportString string
---@return ImportDataStreamMixin
function ExportUtil.MakeImportDataStream(exportString) end
