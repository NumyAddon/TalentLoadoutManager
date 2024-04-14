--- Only some of the types described here, are part of the public API.

--- @class TalentLoadoutManager_LevelingBuildEntry
--- @field nodeID number
--- @field entryID ?number # Only present for choice nodes
--- @field targetRank number

--- @class TalentLoadoutManager_LoadoutDisplayInfo
--- @field id number|string  - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts
--- @field displayName string
--- @field loadoutInfo TalentLoadoutManager_LoadoutInfo
--- @field owner string|nil
--- @field playerIsOwner boolean
--- @field isBlizzardLoadout boolean
--- @field parentMapping number[]|nil - only set if this is a custom loadout, [playerName-realmName] = parentLoadoutID, position [0] contains the current player's parentLoadoutID if any
--- @field classID number
--- @field specID number

--- @class TalentLoadoutManager_LoadoutInfo
--- @field name string
--- @field selectedNodes string - serialized loadout
--- @field id number|string - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts

--- @class TalentLoadoutManager_DeserializedLoadout
--- @field nodeID number
--- @field entryID number
--- @field spellID number
--- @field rank number
--- @field levelingInfo table<number, number> - [level] = targetRank

--- @class TalentLoadoutManagerAPI_LoadoutInfo
--- @field id number|string - custom loadouts are prefixed with "C_" to avoid collisions with blizzard loadouts
--- @field displayName string - blizzard loadouts are prefixed with a small Blizzard texture icon
--- @field name string - the raw loadout name
--- @field serializedNodes string - serialized loadout, this is NOT an export string, but rather an internal TLM format
--- @field owner string|nil - player-realm, only applies to Blizzard loadouts
--- @field playerIsOwner boolean - false for Blizzard loadouts owned by alts
--- @field isBlizzardLoadout boolean
--- @field parentMapping number[]|nil - only set if this is a custom loadout, [playerName-realmName] = parentLoadoutID, position [0] contains the current player's parentLoadoutID if any
--- @field classID number
--- @field specID number