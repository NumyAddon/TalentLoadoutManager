local _, ns = ...;
local L = ns.L;

L["Talent Loadout Manager"] = "Talent Loadout Manager";
L["Create"] = "Create";
L["Import"] = "Import";
L["Save"] = "Save";
L["Config"] = "Config";
L["Load"] = "Load";
L["Load & Apply"] = "Load & Apply";
L["Export"] = "Export";
L["Rename"] = "Rename";
L["Delete"] = "Delete";
L["Locked"] = "Locked";
L["Link to chat"] = "Link to chat";

L["Create a new custom loadout"] = "Create a new custom loadout";
L["Import a custom loadout from a string"] = "Import a custom loadout from a string";
L["Save the current talents into the currently selected loadout"] = "Save the current talents into the currently selected loadout";
L["Open the configuration UI"] = "Open the configuration UI";

L["Toggle Sidebar"] = "Toggle Sidebar";
L["Shift + Click to move sidebar"] = "|cffeda55fShift + Click|r to move the side bar to the other side of the UI.";
L["Right-Click to move sidebar inside"] = "|cffeda55fRight-Click|r to move the side bar to the inside side of the UI.";

L["Loadout name hint"] = "Anything before the first '||' character will not display. This allows you to sort loadouts by adding a prefix.";
L["Rename loadout (%s)"] = "Rename loadout (%s)";
L["Create custom loadout"] = "Create custom loadout";
L["Delete loadout (%s)?"] = "Delete loadout (%s)?";
L["Remove loadout from list (%s)?"] = "Remove loadout from list (%s)?";
L["Remove all loadouts from %s from the list?"] = "Remove all loadouts from %s from the list?";
L["CTRL-C to copy"] = "CTRL-C to copy";
L["CTRL-C to copy %s"] = "CTRL-C to copy %s";

L["Import Custom Loadout"] = "Import Custom Loadout";
L["Import control label"] = "%s (Icy-veins calculator links are also supported)";
L["Automatically Apply the loadout on import"] = "Automatically Apply the loadout on import";
L["Auto apply on import tooltip"] = "If checked, the loadout will automatically be applied to your character when you import it.";
L["Import into currently selected custom loadout"] = "Import into currently selected custom loadout";
L["Import into current loadout tooltip"] = "If checked, the imported build will be imported into the currently selected loadout.";
L["*importing into current loadout*"] = "*importing into current loadout*";

L["Left-Click to %s this loadout"] = "Left-Click to %s this loadout";
L["Shift-Click to link to chat"] = "Shift-Click to link to chat";
L["Right-Click for options"] = "Right-Click for options";

L["Save current talents into loadout"] = "Save current talents into loadout";
L["Lock loadout"] = "Lock loadout";
L["Lock loadout tooltip"] = "Locking a loadout blocks you from saving changes to it.";
L["Set Blizzard base loadout"] = "Set Blizzard base loadout";
L["Open in TalentTreeViewer"] = "Open in TalentTreeViewer";
L["Remove from list"] = "Remove from list";
L["Remove all loadouts from this character from the list"] = "Remove all loadouts from this character from the list";
L["Permanently hide all loadouts from this character"] = "Permanently hide all loadouts from this character";
L["Loadouts from %s are now hidden. You can reset this in the config."] = "Loadouts from %s are now hidden. You can reset this in the config.";

L["Custom Loadout %s"] = "Custom Loadout %s";
L["BlizzMove incompatible"] = "%s is not compatible with the current version of BlizzMove, please update.";

L["Version: %s"] = "Version: %s";
L["Leveling build description"] = [[TalentLoadoutManager supports importing leveling builds, through any import string or ingame link that includes leveling info, or through IcyVeins calculator links.
You can create a leveling build yourself, either using the IcyVeins talent calculator, or ingame, using the Talent Tree Viewer addon
]];
L["Auto Re-Apply Loadout on Level Up"] = "Auto Re-Apply Loadout on Level Up";
L["Auto Re-Apply Loadout on Level Up desc"] = "Automatically re-apply your current talent loadout when you level up.";
L["Auto Scale"] = "Auto Scale";
L["Auto Scale desc"] = "Automatically scale the talent frame to fit the screen. (disabled if BlizzMove or TalentTreeTweaks is loaded)";
L["Auto Position"] = "Auto Position";
L["Auto Position desc"] = "Automatically reposition the talent frame to the center of the screen.";
L["Auto Apply"] = "Auto Apply";
L["Auto Apply desc"] = "Automatically apply the talent loadout when you import or switch talents.";
L["Add to SimC"] = "Add to SimC";
L["Add to SimC desc"] = "Automatically add custom talent loadouts to the SimulationCraft addon when /simc is used.";
L["Reset Hidden Characters"] = "Reset Hidden Characters";
L["Reset Hidden Characters desc"] = "Resets characters whose loadouts were hidden in the sidebar.";
L["Sidebar Colors"] = "Sidebar Colors";
L["Selected Loadout Text"] = "Selected Loadout Text";
L["Selected Loadout Text desc"] = "The text color of the selected loadout in the side bar.";
L["Selected Loadout Background"] = "Selected Loadout Background";
L["Selected Loadout Background desc"] = "The background color of the selected loadout in the side bar.";
L["Selected Loadout Highlight"] = "Selected Loadout Highlight";
L["Selected Loadout Highlight desc"] = "The background color of the selected loadout in the side bar when hovered.";
L["Loadout Text"] = "Loadout Text";
L["Loadout Text desc"] = "The text color of loadouts in the side bar.";
L["Loadout Background"] = "Loadout Background";
L["Loadout Background desc"] = "The background color of loadouts in the side bar.";
L["Loadout Highlight"] = "Loadout Highlight";
L["Loadout Highlight desc"] = "The background color of loadouts in the side bar when hovered.";
L["Sidebar Background"] = "Sidebar Background";
L["Sidebar Background desc"] = "The background color of the side bar.";
L["Reset All Colors"] = "Reset All Colors";
L["Reset All Colors desc"] = "Reset all side bar colors to their defaults.";

L["Failed to serialize loadout %s"] = "Failed to serialize loadout %s";
L["You have not unlocked talents yet."] = "You have not unlocked talents yet.";
L["Too many blizzard loadouts"] = "You have too many blizzard loadouts. Please delete one in order to switch to a custom loadout.";
L["Failed to create new loadout."] = "Failed to create new loadout.";
L["Failed to fully apply loadout. %s entries could not be purchased."] = "Failed to fully apply loadout. %s entries could not be purchased.";
L["Failed to commit loadout."] = "Failed to commit loadout.";
L["Zygor warning"] = "Zygor Guides' talent advisor is enabled. This is known to cause game freezes when changing loadouts. Disable this feature and report it to the author of Zygor Guides.";

L["Automatically re-applying loadout"] = "Automatically re-applying loadout %s, go to /TLM to disable this behavior.";
L["New Talent Learned:"] = "New Talent Learned:";
L["Talent Upgraded:"] = "Talent Upgraded:";
L["to rank"] = "to rank";

L["Import string is corrupt"] = "Import string is corrupt, node type mismatch at nodeID %d. First option will be selected.";
L["IcyVeins import error"] = "Error while importing IcyVeins URL: Could not find node for index %s - %s";
L["Invalid URL"] = "Invalid URL";
L["Wrong class"] = "Wrong class";
L["Loadout not found"] = "Loadout not found";
L["Could not find newly imported loadout"] = "Could not find newly imported loadout";
