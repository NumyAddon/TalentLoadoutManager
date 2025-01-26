-- Only run if TTT (with its taint module) is missing
-- This module is pretty much a copy/paste my TTT taint module
if C_AddOns.IsAddOnLoaded('TalentTreeTweaks') then return; end

local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;

--- @class TLM_ReduceTaintModule: AceModule, AceHook-3.0
local Module = TLM:NewModule('ReduceTaint', 'AceHook-3.0');

function Module:OnInitialize()
    Menu.ModifyMenu('MENU_CLASS_TALENT_PROFILE', function(dropdown, rootDescription, contextData)
        if not self:IsEnabled() then return; end
        self:OnLoadoutMenuOpen(dropdown, rootDescription);
    end);
    self.copyDialogName = 'TalentLoadoutManager_ReduceTaint_CopyTextDialog';
    StaticPopupDialogs[self.copyDialogName] = {
        text = 'CTRL-C to copy %s',
        button1 = CLOSE,
        OnShow = function(dialog, data)
            local function HidePopup()
                dialog:Hide();
            end
            dialog.editBox:SetScript('OnEscapePressed', HidePopup);
            dialog.editBox:SetScript('OnEnterPressed', HidePopup);
            dialog.editBox:SetScript('OnKeyUp', function(_, key)
                if IsControlKeyDown() and key == 'C' then
                    HidePopup();
                end
            end);
            dialog.editBox:SetMaxLetters(0);
            dialog.editBox:SetText(data);
            dialog.editBox:HighlightText();
        end,
        hasEditBox = true,
        editBoxWidth = 240,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };
end

function Module:OnEnable()
    EventUtil.ContinueOnAddOnLoaded('Blizzard_PlayerSpells', function()
        self:SetupHook();
    end);
    self:HandleActionBarEventTaintSpread();
end

function Module:OnDisable()
    self:UnhookAll();
end

--- @return PlayerSpellsFrame_TalentsFrame
function Module:GetTalentFrame()
    return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame;
end
--- @return PlayerSpellsFrame
function Module:GetTalentContainerFrame()
    return PlayerSpellsFrame;
end
function Module:CopyText(text, optionalTitleSuffix)
    StaticPopup_Show(self.copyDialogName, optionalTitleSuffix or '', nil, text);
end

function Module:SetupHook()
    local talentsTab = self:GetTalentFrame();
    talentsTab:RegisterCallback(TalentFrameBaseMixin.Event.TalentButtonAcquired, self.OnTalentButtonAcquired, self);
    for talentButton in talentsTab:EnumerateAllTalentButtons() do
        self:OnTalentButtonAcquired(talentButton);
    end
    self:SecureHook(talentsTab, 'ShowSelections', 'OnShowSelections');

    -- ToggleTalentFrame starts of with a talentContainerFrame:SetInspecting call, which has a high likelihood of tainting execution
    self:SecureHook('ShowUIPanel', 'OnShowUIPanel')
    self:SecureHook('HideUIPanel', 'OnHideUIPanel')

    self:SecureHook(talentsTab, 'UpdateInspecting', 'OnUpdateInspecting');
    self:ReplaceCopyLoadoutButton(talentsTab);

    self:HandleMultiActionBarTaint();
end

function Module:OnUpdateInspecting(talentsTab)
    local isInspecting = talentsTab:IsInspecting();
    if not isInspecting then
        self.cachedInspectExportString = nil;

        return;
    end
    self.cachedInspectExportString = talentsTab:GetInspectUnit() and C_Traits.GenerateInspectImportString(talentsTab:GetInspectUnit()) or talentsTab:GetInspectString();
end

function Module:ReplaceCopyLoadoutButton(talentsTab)
    talentsTab.InspectCopyButton:SetOnClickHandler(function()
        local loadoutString =
            self.cachedInspectExportString
            or (talentsTab:GetInspectUnit() and C_Traits.GenerateInspectImportString(talentsTab:GetInspectUnit()) or talentsTab:GetInspectString());
        if loadoutString and (loadoutString ~= '') then
            self:CopyText(loadoutString, 'Inspected Build');
        end
    end);
end

local function purgeKey(table, key)
    TextureLoadingGroupMixin.RemoveTexture({textures = table}, key);
end
local function makeFEnvReplacement(original, replacement)
    local fEnv = {};
    setmetatable(fEnv, { __index = function(t, k)
        return replacement[k] or original[k];
    end});
    return fEnv;
end

function Module:HandleMultiActionBarTaint()
    local talentContainerFrame = self:GetTalentContainerFrame();
    self.originalOnShowFEnv = self.originalOnShowFEnv or getfenv(talentContainerFrame.OnShow);

    setfenv(talentContainerFrame.OnShow, makeFEnvReplacement(self.originalOnShowFEnv, {
        PlayerSpellsMicroButton = {
            EvaluateAlertVisibility = function()
                HelpTip:HideAllSystem('MicroButtons');
            end,
        },
        MultiActionBar_ShowAllGrids = nop,
        UpdateMicroButtons = function() self:TriggerMicroButtonUpdate() end,
    }));

    self:SecureHook(FrameUtil, 'UnregisterFrameForEvents', function(frame)
        if frame == talentContainerFrame then
            self:MakeOnHideSafe();
        end
    end);
    local microButton = TalentMicroButton or PlayerSpellsMicroButton;
    if
        self.originalOnShowFEnv
        and microButton and microButton.HasTalentAlertToShow
        and not self:IsHooked(microButton, 'HasTalentAlertToShow')
    then
        self:SecureHook(microButton, 'HasTalentAlertToShow', function()
            purgeKey(microButton, 'canUseTalentUI');
            purgeKey(microButton, 'canUseTalentSpecUI');
        end);
    end
end

function Module:MakeOnHideSafe()
    local talentContainerFrame = self:GetTalentContainerFrame();
    if not issecurevariable(talentContainerFrame, 'lockInspect') then
        if not talentContainerFrame.lockInspect then
            purgeKey(talentContainerFrame, 'lockInspect');
        else
            -- get blizzard to set the value to true
            TextureLoadingGroupMixin.AddTexture({textures = talentContainerFrame}, 'lockInspect');
        end
    end
    local isInspecting = talentContainerFrame:IsInspecting();
    if not issecurevariable(talentContainerFrame, 'inspectUnit') then
        purgeKey(talentContainerFrame, 'inspectUnit');
    end
    if not issecurevariable(talentContainerFrame, 'inspectString') then
        purgeKey(talentContainerFrame, 'inspectString');
    end
    if isInspecting then
        purgeKey(talentContainerFrame, 'inspectString');
        purgeKey(talentContainerFrame, 'inspectUnit');
        RunNextFrame(function()
            talentContainerFrame:SetInspecting(nil, nil, nil);
        end);
    end
end

function Module:TriggerMicroButtonUpdate()
    local cvarName = 'Numy_TalentLoadoutManager';
    -- the LFDMicroButton will trigger UpdateMicroButtons() in its OnEvent, without checking the event itself.
    -- CVAR_UPDATE is easy enough to trigger at will, so we make use of that
    LFDMicroButton:RegisterEvent('CVAR_UPDATE');
    if not self.cvarRegistered then
        C_CVar.RegisterCVar(cvarName);
        self.cvarRegistered = true;
    end
    C_CVar.SetCVar(cvarName, GetCVar(cvarName) == '1' and '0' or '1');
    LFDMicroButton:UnregisterEvent('CVAR_UPDATE');
end

function Module:OnShowUIPanel(frame)
    if frame ~= self:GetTalentContainerFrame() then return end
    if (frame.IsShown and not frame:IsShown()) then
        -- if possible, force show the frame, ignoring the INTERFACE_ACTION_BLOCKED message
        frame:Show()
    end
end

function Module:OnHideUIPanel(frame)
    if frame ~= self:GetTalentContainerFrame() then return end
    if (frame.IsShown and frame:IsShown()) then
        -- if possible, force hide the frame, ignoring the INTERFACE_ACTION_BLOCKED message
        frame:Hide()
    end
end

function Module:OnShowSelections()
    for _, button in pairs(self:GetTalentFrame().SelectionChoiceFrame.selectionFrameArray) do
        self:OnTalentButtonAcquired(button);
    end
end

local function replacedShareButtonCallback()
    local exportString = Module:GetTalentFrame():GetLoadoutExportString();
    Module:CopyText(exportString, 'Talent Loadout String');
end

function Module:OnLoadoutMenuOpen(dropdown, rootDescription)
    if not self:ShouldReplaceShareButton() then return; end

    for _, elementDescription in rootDescription:EnumerateElementDescriptions() do
        if elementDescription.text == TALENT_FRAME_DROP_DOWN_EXPORT then
            for _, subElementDescription in elementDescription:EnumerateElementDescriptions() do
                -- for unlock restrictions module: subElementDescription:SetEnabled(function() return true end); -- try without func wrapper too
                if subElementDescription.text == TALENT_FRAME_DROP_DOWN_EXPORT_CLIPBOARD then
                    subElementDescription:SetResponder(replacedShareButtonCallback);
                end
            end
        end
    end
end

function Module:ShouldReplaceShareButton()
    return not issecurevariable(self:GetTalentFrame(), 'configID');
end

function Module:HandleActionBarEventTaintSpread()
    -- no longer works after 11.1.0, but hopefully hasn't been needed since 11.0.7 either
    if select(4, GetBuildInfo()) >= 110100 then return; end

    local events = {
        ['PLAYER_ENTERING_WORLD'] = true,
        ['ACTIONBAR_SLOT_CHANGED'] = true,
        ['UPDATE_BINDINGS'] = true,
        ['GAME_PAD_ACTIVE_CHANGED'] = true,
        ['UPDATE_SHAPESHIFT_FORM'] = true,
        ['ACTIONBAR_UPDATE_COOLDOWN'] = true,
        ['PET_BAR_UPDATE'] = true,
        ['PLAYER_MOUNT_DISPLAY_CHANGED'] = true,
    };
    local petUnitEvents = {
        ['UNIT_FLAGS'] = true,
        ['UNIT_AURA'] = true,
    }
    local function registerActionButtonEvents(actionButton)
        --@debug@
        hooksecurefunc(actionButton, 'UnregisterEvent', function(_, event)
            if events[event] then
                print('TLM-ReduceTaint Module Debug:', actionButton:GetName(), 'UnregisterEvent', event);
            end
        end);
        --@end-debug@
        for event in pairs(events) do
            actionButton:RegisterEvent(event);
        end
        for petUnitEvent in pairs(petUnitEvents) do
            actionButton:RegisterUnitEvent(petUnitEvent, 'pet');
        end
    end
    for _, actionButton in pairs(ActionBarButtonEventsFrame.frames) do
        registerActionButtonEvents(actionButton);
    end
    hooksecurefunc(ActionBarButtonEventsFrame, 'RegisterFrame', function(_, actionButton)
        registerActionButtonEvents(actionButton);
    end);
    for event in pairs(events) do
        ActionBarButtonEventsFrame:UnregisterEvent(event);
    end
    for petUnitEvent in pairs(petUnitEvents) do
        ActionBarButtonEventsFrame:UnregisterEvent(petUnitEvent, 'pet');
    end
end

function Module:SetActionBarHighlights(talentButton, shown)
    local notMissing = ActionButtonUtil and ActionButtonUtil.ActionBarActionStatus and ActionButtonUtil.ActionBarActionStatus.NotMissing;
    local spellID = talentButton:GetSpellID();
    if (spellID and (talentButton.GetActionBarStatus and talentButton:GetActionBarStatus() == notMissing)) then
        self:HandleBlizzardActionButtonHighlights(shown and spellID);
        self:HandleLibActionButtonHighlights(shown and spellID);
    end
end

function Module:HandleBlizzardActionButtonHighlights(spellID)
    local ON_BAR_HIGHLIGHT_MARKS = spellID and tInvert(C_ActionBar.FindSpellActionButtons(spellID) or {}) or {};
    for _, actionButton in pairs(ActionBarButtonEventsFrame.frames) do
        if ( actionButton.SpellHighlightTexture and actionButton.SpellHighlightAnim ) then
            SharedActionButton_RefreshSpellHighlight(actionButton, ON_BAR_HIGHLIGHT_MARKS[actionButton.action]);
        end
    end
end

function Module:HandleLibActionButtonHighlights(spellID)
    local name = 'LibActionButton-1.';
    for mayor, lib in LibStub:IterateLibraries() do
        if mayor:sub(1, string.len(name)) == name then
            for button in pairs(lib:GetAllButtons()) do
                if button.SpellHighlightTexture and button.SpellHighlightAnim and button.GetSpellId then
                    local shown = spellID and button:GetSpellId() == spellID;
                    SharedActionButton_RefreshSpellHighlight(button, shown);
                end
            end
        end
    end
end

local function ShowActionBarHighlightsReplacement(talentButton)
    Module:SetActionBarHighlights(talentButton, true);
end
local function HideActionBarHighlightsReplacement(talentButton)
    Module:SetActionBarHighlights(talentButton, false);
end

function Module:OnTalentButtonAcquired(button)
    button.ShowActionBarHighlights = ShowActionBarHighlightsReplacement;
    button.HideActionBarHighlights = HideActionBarHighlightsReplacement;
end
