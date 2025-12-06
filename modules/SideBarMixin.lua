local addonName, ns = ...;

local ChatEdit_InsertLink = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
local ChatFrame_OpenChat = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat

--- @class TLM_SideBarMixin: AceModule, AceHook-3.0
local SideBarMixin = {};
ns.SideBarMixin = SideBarMixin;

--- @type TalentLoadoutManagerConfig
local Config = ns.Config;

--- @type TalentLoadoutManagerAPI
local API = TalentLoadoutManagerAPI;
local GlobalAPI = TalentLoadoutManagerAPI.GlobalAPI;
local CharacterAPI = TalentLoadoutManagerAPI.CharacterAPI;

SideBarMixin.IntegrateWithBlizzMove = true;
SideBarMixin.ImplementAutoApply = false;
SideBarMixin.ShowAnimationOnImport = false;
SideBarMixin.ImplementTTTMissingWarning = false;
SideBarMixin.ShowLoadAndApply = false;
SideBarMixin.ShowShowInTTV = false;

local LEVEL_CAP = 70;
local SETTING_SUFFIX_COLLAPSED = "_Collapsed";
local SETTING_SUFFIX_ANCHOR_LOCATION = "_AnchorLocation";
local ANCHOR_LEFT = 0;
local ANCHOR_RIGHT = 1;
local LOCK_MARKUP = CreateAtlasMarkup("AdventureMapIcon-Lock", 16, 16) .. " ";

function SideBarMixin:OnInitialize()
    local loadoutNameSubText = "Anything before the first '||' character will not display. This allows you to sort loadouts by adding a prefix.";

    local moduleName = self.name;
    self.renameDialogName = moduleName .. "_RenameLoadout";
    StaticPopupDialogs[self.renameDialogName] = {
        text = NORMAL_FONT_COLOR:WrapTextInColorCode("Rename loadout (%s)") .. "\n" .. loadoutNameSubText,
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        --- @param dialog StaticPopupTemplate
        --- @param data TLM_SideBarLoadoutInfo
        OnShow = function(dialog, data)
            --- @type StaticPopupTemplate_EditBox
            local editBox = dialog:GetEditBox();
            editBox:SetText(data.name);
            editBox:HighlightText();
            editBox:SetScript("OnEscapePressed", function()
                dialog:Hide();
            end);
            editBox:SetScript("OnEnterPressed", function()
                dialog:GetButtons()[1]:Click();
            end);
        end,
        --- @param dialog StaticPopupTemplate
        --- @param data TLM_SideBarLoadoutInfo
        OnAccept = function(dialog, data)
            local newName = dialog:GetEditBox():GetText();
            GlobalAPI:RenameLoadout(data.id, newName);
            dialog:Hide();
        end,
        --- @param self StaticPopupTemplate_EditBox
        EditBoxOnTextChanged = function(self)
            --- @type StaticPopupTemplate
            local dialog = self:GetParent();
            if self:GetText() == "" then
                dialog:GetButtons()[1]:Disable();
            else
                dialog:GetButtons()[1]:Enable();
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.createDialogName = moduleName .. "_CreateLoadout";
    StaticPopupDialogs[self.createDialogName] = {
        text = NORMAL_FONT_COLOR:WrapTextInColorCode("Create custom loadout") .. "\n" .. loadoutNameSubText,
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        --- @param dialog StaticPopupTemplate
        OnShow = function(dialog)
            --- @type StaticPopupTemplate_EditBox
            local editBox = dialog:GetEditBox();
            editBox:SetScript("OnEscapePressed", function()
                dialog:Hide();
            end);
            editBox:SetScript("OnEnterPressed", function()
                dialog:GetButtons()[1]:Click();
            end);
        end,
        --- @param dialog StaticPopupTemplate
        OnAccept = function(dialog)
            local name = dialog:GetEditBox():GetText();
            self:DoCreate(name)
            dialog:Hide();
        end,
        --- @param self StaticPopupTemplate_EditBox
        EditBoxOnTextChanged = function(self)
            --- @type StaticPopupTemplate
            local dialog = self:GetParent();
            if self:GetText() == "" then
                dialog:GetButtons()[1]:Disable();
            else
                dialog:GetButtons()[1]:Enable();
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.deleteDialogName = moduleName .. "_DeleteLoadout";
    StaticPopupDialogs[self.deleteDialogName] = {
        text = "Delete loadout (%s)?",
        button1 = OKAY,
        button2 = CANCEL,
        --- @param dialog StaticPopupTemplate
        --- @param data TLM_SideBarLoadoutInfo
        OnAccept = function(dialog, data)
            GlobalAPI:DeleteLoadout(data.id);
            dialog:Hide();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.removeFromListDialogName = moduleName .. "_RemoveLoadout";
    StaticPopupDialogs[self.removeFromListDialogName] = {
        text = "Remove loadout from list (%s)?",
        button1 = OKAY,
        button2 = CANCEL,
        --- @param dialog StaticPopupTemplate
        --- @param data TLM_SideBarLoadoutInfo
        OnAccept = function(dialog, data)
            GlobalAPI:RemoveLoadoutFromStorage(data.id);
            dialog:Hide();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.removeFromListBulkDialogName = moduleName .. "_RemoveLoadoutBulk";
    StaticPopupDialogs[self.removeFromListBulkDialogName] = {
        text = "Remove all loadouts from %s from the list?",
        button1 = OKAY,
        button2 = CANCEL,
        --- @param dialog StaticPopupTemplate
        --- @param data TLM_SideBarLoadoutInfo
        OnAccept = function(dialog, data)
            self:RemoveAllLoadoutsByOwner(data.owner);
            dialog:Hide();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.copyDialogName = moduleName .. "_CopyText";
    StaticPopupDialogs[self.copyDialogName] = {
        text = "CTRL-C to copy",
        button1 = CLOSE,
        --- @param dialog StaticPopupTemplate
        --- @param data string
        OnShow = function(dialog, data)
            local function HidePopup()
                dialog:Hide();
            end
            --- @type StaticPopupTemplate_EditBox
            local editBox = dialog:GetEditBox();
            editBox:SetScript("OnEscapePressed", HidePopup);
            editBox:SetScript("OnEnterPressed", HidePopup);
            editBox:SetScript("OnKeyUp", function(_, key)
                if IsControlKeyDown() and (key == 'C' or key == 'X') then
                    HidePopup();
                end
            end);
            editBox:SetMaxLetters(0);
            editBox:SetText(data);
            editBox:HighlightText();
        end,
        hasEditBox = true,
        editBoxWidth = 240,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.genericPopupDialogName = moduleName .. "_GenericPopup";
    StaticPopupDialogs[self.genericPopupDialogName] = {
        text = "%s",
        button1 = OKAY,
        button2 = nil,
        timeout = 0,
        OnAccept = function() end,
        OnCancel = function() end,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };
end

function SideBarMixin:OnEnable()
    error('override in implementation');
    -- override in implementation: should SetupHook on relevant addonLoaded
end

function SideBarMixin:OnDisable()
    self:UnhookAll();

    API:UnregisterCallback(API.Event.LoadoutListUpdated, self);
    Config:UnregisterCallback(Config.Event.CharacterVisibilityChanged, self);
end

function SideBarMixin:SetupHook()
    if not self.SideBar then
        self.SideBar, self.DataProvider = self:CreateSideBar();
        self:SetCollapsed(Config:GetConfig(self.name .. SETTING_SUFFIX_COLLAPSED));
        self:UpdatePointsForAnchorLocation();
        self:TryIntegrateWithBlizzMove();
    end
    if not self.importDialog then
        self.importDialog = self:CreateImportDialog();
    end
    local talentsTab = self:GetTalentsTab();
    self:SecureHookScript(talentsTab, "OnShow", "OnTalentsTabShow");
    self:SecureHook(talentsTab, "OnUpdate", "OnTalentsChanged");

    API:RegisterCallback(API.Event.LoadoutListUpdated, self.RefreshSideBarData, self);
    Config:RegisterCallback(Config.Event.CharacterVisibilityChanged, self.RefreshSideBarData, self);
end

do
    --- @return PlayerSpellsFrame_TalentsFrame|TalentViewer_ClassTalentsFrameTemplate
    function SideBarMixin:GetTalentsTab()
        error('override in implementation');
    end

    --- @param name string
    function SideBarMixin:DoCreate(name)
        error('override in implementation');
    end

    --- @return TalentLoadoutManagerAPI_LoadoutInfo[]
    function SideBarMixin:GetLoadouts()
        error('override in implementation');
    end

    --- @return TalentLoadoutManagerAPI_LoadoutInfo|nil - selected loadout's info, if any
    function SideBarMixin:GetActiveLoadout(forceRefresh)
        error('override in implementation');
    end

    function SideBarMixin:DoImport(importText, loadoutName, autoApply)
        error('override in implementation');
    end

    function SideBarMixin:DoImportIntoCurrent(importText, autoApply)
        error('override in implementation');
    end

    --- @param entry TLM_SideBarDataProviderEntry
    function SideBarMixin:GetDefaultActionText(entry)
        error('override in implementation');
    end

    function SideBarMixin:GetExportString()
        error('override in implementation');
    end

    function SideBarMixin:UpdateCustomLoadoutWithCurrentTalents(loadoutID)
        error('override in implementation');
    end

    function SideBarMixin:DoLoad(loadoutID, autoApply)
        error('override in implementation');
    end

    --- @return BlizzMoveAPI_AddonFrameTable
    function SideBarMixin:GetBlizzMoveFrameTable()
        error('override in implementation');
    end
end

function SideBarMixin:OnTalentsChanged()
    if self.talentChangePending then return; end
    self.talentChangePending = true
    RunNextFrame(function()
        self.talentChangePending = false

        self:SaveButtonUpdateEnableState();
    end);
end

function SideBarMixin:SaveButtonUpdateEnableState()
    local activeLoadout = self:GetActiveLoadout();
    local identicalTalents = false;
    if activeLoadout then
        local savedExportString = GlobalAPI:GetExportString(activeLoadout.id);
        local currentExportString = self:GetExportString();

        if savedExportString == currentExportString then
            identicalTalents = true;
        elseif savedExportString and currentExportString and savedExportString ~= "" and currentExportString ~= "" then
            local serializedSavedExportString = GlobalAPI:SerializeLoadoutString(savedExportString);
            local serializedCurrentExportString = GlobalAPI:SerializeLoadoutString(currentExportString);

            identicalTalents = serializedSavedExportString == serializedCurrentExportString;
        end
    end

    self.SideBar.SaveButton:SetEnabled(
        activeLoadout
        and not activeLoadout.isBlizzardLoadout
        and not activeLoadout.isLocked
        and not identicalTalents
    );
end

function SideBarMixin:OnTalentsTabShow(frame)
    self:UpdateScaleForFit(frame:GetParent());
    self:UpdatePosition(frame:GetParent());
    self:RefreshSideBarData();
end

function SideBarMixin:UpdateScaleForFit(frame)
    if not Config:GetConfig('autoScale') then return end

    local extraHeight = 270;
    local extraWidth = 200 + (self.SideBar:GetWidth() * 1.5);

    local horizRatio = UIParent:GetWidth() / GetUIPanelWidth(frame, extraWidth);
    local vertRatio = UIParent:GetHeight() / GetUIPanelHeight(frame, extraHeight);

    frame:SetScale(min(horizRatio, vertRatio, 1));
end

function SideBarMixin:UpdatePosition(frame)
    if not Config:GetConfig('autoPosition') then return; end
    if frame:IsProtected() and InCombatLockdown() then return; end

    local offsetDirection = self:GetAnchorLocation() == ANCHOR_LEFT and 1 or -1;
    local replacePoint = true;
    local xOffset = (self.SideBar:GetWidth() / 2) * offsetDirection;
    local yOffset = -41;
    if frame:GetNumPoints() > 0 then
        local point, relativeTo, relativePoint, foundXOffset;
        point, relativeTo, relativePoint, foundXOffset, yOffset = frame:GetPoint(1);
        replacePoint = false;
        if
            point == "TOP" and relativeTo == UIParent and relativePoint == "TOP"
            and (foundXOffset == 0 or ((foundXOffset - (xOffset * -1))) < 1)
        then
            replacePoint = true;
        end
    end

    if replacePoint then
        frame:ClearAllPoints();
        frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset);
    end
end

function SideBarMixin:CreateImportDialog()
    --- main dialog
    local dialog = CreateFrame("Frame", nil, UIParent, "ClassTalentLoadoutDialogTemplate");
    dialog.titleText = "Import Custom Loadout";
    Mixin(dialog, ClassTalentLoadoutImportDialogMixin);
    dialog:SetSize(460, 300);
    dialog:Hide();

    --- import control
    dialog.ImportControl = CreateFrame("Frame", nil, dialog);
    local importControl = dialog.ImportControl;
    importControl.labelText = HUD_CLASS_TALENTS_IMPORT_DIALOG_EDIT_BOX_LABEL .. " (Icy-veins calculator links are also supported)";
    importControl:SetPoint("TOPLEFT", dialog.ContentArea);
    importControl:SetPoint("TOPRIGHT", dialog.ContentArea);
    importControl:SetHeight(100);
    importControl.Label = importControl:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    importControl.Label:SetPoint("TOPLEFT");
    Mixin(importControl, ClassTalentLoadoutImportDialogImportControlMixin);

    importControl.InputContainer = CreateFrame("ScrollFrame", nil, importControl, "InputScrollFrameTemplate");
    importControl.InputContainer:SetPoint("TOPLEFT", importControl.Label, "BOTTOMLEFT", 0, -10);
    importControl.InputContainer:SetPoint("RIGHT");
    importControl.InputContainer:SetPoint("BOTTOM");
    importControl.InputContainer.maxLetters = 1000;
    importControl.InputContainer.instructions = HUD_CLASS_TALENTS_IMPORT_INSTRUCTIONS;
    importControl.InputContainer.hideCharCount = true;
    InputScrollFrame_OnLoad(importControl.InputContainer);

    importControl:OnLoad();
    importControl:SetScript("OnShow", importControl.OnShow);

    --- name control
    dialog.NameControl = CreateFrame("Frame", nil, dialog, "ClassTalentLoadoutDialogNameControlTemplate");
    local nameControl = dialog.NameControl;
    nameControl.labelText = HUD_CLASS_TALENTS_IMPORT_DIALOG_NAME_LABEL;
    nameControl.EditBox:SetMaxLetters(0);
    nameControl:SetPoint("TOPLEFT", importControl, "BOTTOMLEFT", 0, -25);
    nameControl:SetPoint("TOPRIGHT", importControl, "BOTTOMRIGHT", 0, -25);
    Mixin(nameControl, ClassTalentLoadoutImportDialogNameControlMixin);

    nameControl:OnLoad();
    nameControl:SetScript("OnShow", nameControl.OnShow);

    local checkbox
    local addAutoApplyCheckbox = self.ImplementAutoApply
    if addAutoApplyCheckbox then
        --- autoApply checkbox
        dialog.AutoApplyCheckbox = CreateFrame('CheckButton', nil, dialog, 'UICheckButtonTemplate');
        checkbox = dialog.AutoApplyCheckbox;
        checkbox:SetPoint('TOPLEFT', dialog.NameControl, 'BOTTOMLEFT', 0, 5);
        checkbox:SetSize(24, 24);
        checkbox:SetScript('OnEnter', function(cb)
            GameTooltip:SetOwner(cb, 'ANCHOR_RIGHT');
            GameTooltip:SetText(cb.text:GetText());
            GameTooltip:AddLine('If checked, the loadout will automatically be applied to your character when you import it.', 1, 1, 1, true);
            GameTooltip:Show();
        end);
        checkbox:SetScript('OnLeave', function()
            GameTooltip:Hide();
        end);
        checkbox.text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal');
        checkbox.text:SetPoint('LEFT', checkbox, 'RIGHT', 0, 1);
        checkbox.text:SetText(string.format('Automatically Apply the loadout on import'));
        checkbox:SetHitRectInsets(-10, -checkbox.text:GetStringWidth(), -5, 0);
    end

    -- ImportIntoCurrentLoadout checkbox
    dialog.ImportIntoCurrentLoadoutCheckbox = CreateFrame('CheckButton', nil, dialog, 'UICheckButtonTemplate');
    checkbox = dialog.ImportIntoCurrentLoadoutCheckbox;
    checkbox:SetPoint('TOPLEFT', addAutoApplyCheckbox and dialog.AutoApplyCheckbox or dialog.NameControl, 'BOTTOMLEFT', 0, 5);
    checkbox:SetSize(24, 24);
    checkbox:SetScript('OnEnter', function(cb)
        GameTooltip:SetOwner(cb, 'ANCHOR_RIGHT');
        GameTooltip:SetText(cb.text:GetText());
        GameTooltip:AddLine('If checked, the imported build will be imported into the currently selected loadout.', 1, 1, 1);
        GameTooltip:Show();
    end);
    checkbox:SetScript('OnLeave', function()
        GameTooltip:Hide();
    end);
    local function checkboxOnChange(cb)
        local checked = cb:IsShown() and cb:GetChecked();
        local dialog = cb:GetParent();
        dialog.NameControl:SetShown(not checked);
        dialog.NameControl:SetText(checked and '*importing into current loadout*' or '');
        dialog:UpdateAcceptButtonEnabledState();
    end
    checkbox:SetScript('OnClick', checkboxOnChange);
    checkbox:SetScript('OnHide', checkboxOnChange);
    checkbox:SetScript('OnShow', checkboxOnChange);
    checkbox.text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal');
    checkbox.text:SetPoint('LEFT', checkbox, 'RIGHT', 0, 1);
    checkbox.text:SetText(string.format('Import into currently selected custom loadout'));
    checkbox:SetHitRectInsets(-10, -checkbox.text:GetStringWidth(), -5, 0);

    --- accept button
    dialog.AcceptButton = CreateFrame("Button", nil, dialog, "ClassTalentLoadoutDialogButtonTemplate");
    local acceptButton = dialog.AcceptButton;
    acceptButton:SetText(HUD_CLASS_TALENTS_IMPORT_LOADOUT_ACCEPT_BUTTON);
    acceptButton.disabledTooltip = HUD_CLASS_TALENTS_IMPORT_ERROR_IMPORT_STRING_AND_NAME;
    acceptButton:SetPoint("BOTTOMRIGHT", dialog.ContentArea, "BOTTOM", -5, 0);

    --- cancel button
    dialog.CancelButton = CreateFrame("Button", nil, dialog, "ClassTalentLoadoutDialogButtonTemplate");
    local cancelButton = dialog.CancelButton;
    cancelButton:SetText(CANCEL);
    cancelButton:SetPoint("BOTTOMLEFT", dialog.ContentArea, "BOTTOM", 5, 0);

    dialog.OnAccept = function(dialog)
        if dialog.AcceptButton:IsEnabled() then
            local importText = dialog.ImportControl:GetText();
            local loadoutName = dialog.NameControl:GetText();
            local autoApply = addAutoApplyCheckbox and dialog.AutoApplyCheckbox:GetChecked();
            local importIntoCurrentLoadout = dialog.ImportIntoCurrentLoadoutCheckbox:IsShown() and dialog.ImportIntoCurrentLoadoutCheckbox:GetChecked();

            local result, errorOrNil;
            if not importIntoCurrentLoadout then
                result, errorOrNil = self:DoImport(importText, loadoutName, autoApply);
            else
                result, errorOrNil = self:DoImportIntoCurrent(importText, autoApply);
            end

            if result then
                StaticPopupSpecial_Hide(dialog);
                if self.ShowAnimationOnImport then self:TryShowLoadoutCompleteAnimation(); end
            elseif errorOrNil then
                StaticPopup_Show(self.genericPopupDialogName, ERROR_COLOR:WrapTextInColorCode(errorOrNil));
            end
        end
    end

    dialog:OnLoad();
    dialog:SetScript("OnShow", function()
        local shouldShowImportIntoCurrent = self.activeLoadout and not self.activeLoadout.isBlizzardLoadout
        dialog.ImportIntoCurrentLoadoutCheckbox:SetShown(shouldShowImportIntoCurrent);
        if addAutoApplyCheckbox then dialog.AutoApplyCheckbox:SetChecked(Config:GetConfig('autoApply')); end
    end);
    dialog:SetScript("OnHide", dialog.OnHide);

    return dialog;
end

function SideBarMixin:OnToggleSideBarButtonClick()
    if IsShiftKeyDown() then
        self:ToggleAnchorLocation();
        return;
    end
    local collapsed = not self:GetCollapsed();
    Config:SetConfig(self.name .. SETTING_SUFFIX_COLLAPSED, collapsed);
    self:SetCollapsed(collapsed);
end

function SideBarMixin:ToggleAnchorLocation()
    local anchorLocation = self:GetAnchorLocation();
    local newAnchorLocation;
    if ANCHOR_LEFT == anchorLocation then
        newAnchorLocation = ANCHOR_RIGHT;
    else
        newAnchorLocation = ANCHOR_LEFT;
    end
    Config:SetConfig(self.name .. SETTING_SUFFIX_ANCHOR_LOCATION, newAnchorLocation);
    self:UpdatePointsForAnchorLocation();
end

function SideBarMixin:UpdatePointsForAnchorLocation()
    local talentsTab = self:GetTalentsTab();
    self.SideBar:ClearAllPoints();
    self.SideBar.ToggleSideBarButton:ClearAllPoints();
    if self:GetAnchorLocation() == ANCHOR_LEFT then
        self.SideBar:SetPoint('TOPRIGHT', talentsTab, 'TOPLEFT', 0, 0);
        self.SideBar.ToggleSideBarButton:SetPoint('RIGHT', talentsTab, 'TOPLEFT', 10, -52);
    else
        self.SideBar:SetPoint('TOPLEFT', self:GetTalentsTab(), 'TOPRIGHT', 0, 0);
        self.SideBar.ToggleSideBarButton:SetPoint('LEFT', talentsTab, 'TOPRIGHT', -10, -52);
    end
    self:SetCollapsed(self:GetCollapsed());

    self:UpdatePosition(talentsTab:GetParent());
end

function SideBarMixin:GetAnchorLocation()
    return Config:GetConfig(self.name .. SETTING_SUFFIX_ANCHOR_LOCATION, ANCHOR_LEFT);
end

function SideBarMixin:SetCollapsed(collapsed)
    local sideBar = self.SideBar;
    sideBar:SetShown(not collapsed);
    local anchorLocation = self:GetAnchorLocation();
    if (not collapsed and ANCHOR_LEFT == anchorLocation) or (collapsed and ANCHOR_RIGHT == anchorLocation) then
        -- arrow pointing right
        sideBar.ToggleSideBarButton:GetNormalTexture():SetTexCoord(0.15625, 0.5, 0.84375, 0.5, 0.15625, 0, 0.84375, 0);
        sideBar.ToggleSideBarButton:GetHighlightTexture():SetTexCoord(0.15625, 1, 0.84375, 1, 0.15625, 0.5, 0.84375, 0.5);
    else
        -- arrow pointing left
        sideBar.ToggleSideBarButton:GetNormalTexture():SetTexCoord(0.15625, 0, 0.84375, 0, 0.15625, 0.5, 0.84375, 0.5);
        sideBar.ToggleSideBarButton:GetHighlightTexture():SetTexCoord(0.15625, 0.5, 0.84375, 0.5, 0.15625, 1, 0.84375, 1);
    end
end

function SideBarMixin:GetCollapsed()
    return Config:GetConfig(self.name .. SETTING_SUFFIX_COLLAPSED, false);
end

function SideBarMixin:CreateSideBar()
    local talentsTab = self:GetTalentsTab();
    --- @class TLM_SideBar : Frame
    local sideBar = CreateFrame("Frame", nil, talentsTab);
    local width = 300;

    sideBar:SetHeight(talentsTab:GetHeight());
    sideBar:SetWidth(width);
    sideBar:SetPoint("TOPRIGHT", talentsTab, "TOPLEFT", 0, 0);

    -- add a background
    sideBar.Background = sideBar:CreateTexture(nil, "BACKGROUND");
    sideBar.Background:SetAllPoints();
    local function updateSideBarColor()
        local color = Config:GetConfig('sideBarBackgroundColor');
        sideBar.Background:SetColorTexture(color.r, color.g, color.b, color.a);
    end
    updateSideBarColor();
    Config:RegisterCallback(Config.Event.OptionValueChanged, function(_, option)
        if option == 'sideBarBackgroundColor' then updateSideBarColor(); end
    end, sideBar);

    -- add a title
    sideBar.Title = sideBar:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    sideBar.Title:SetPoint("TOPLEFT", sideBar, "TOPLEFT", 10, -10);
    sideBar.Title:SetText("Talent Loadout Manager");

    -- add Create button
    sideBar.CreateButton = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.CreateButton:SetSize((width / 2) - 10, 20);
    sideBar.CreateButton:SetText("Create");
    sideBar.CreateButton:SetPoint("TOPLEFT", sideBar.Title, "BOTTOMLEFT", 0, -10);
    sideBar.CreateButton:SetScript("OnClick", function()
        StaticPopup_Show(self.createDialogName);
    end);
    sideBar.CreateButton.tooltipText = "Create a new custom loadout";

    -- add Import button
    sideBar.ImportButton = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.ImportButton:SetSize((width / 2) - 10, 20);
    sideBar.ImportButton:SetText("Import");
    sideBar.ImportButton:SetPoint("TOPLEFT", sideBar.CreateButton, "TOPRIGHT", 0, 0);
    sideBar.ImportButton:SetScript("OnClick", function()
        self.importDialog:ShowDialog();
    end);
    sideBar.ImportButton.tooltipText = "Import a custom loadout from a string";

    -- add a Save button
    sideBar.SaveButton = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.SaveButton:SetSize((width / 2) - 10, 20);
    sideBar.SaveButton:SetText("Save");
    sideBar.SaveButton:SetPoint("TOPLEFT", sideBar.CreateButton, "BOTTOMLEFT", 0, 0);
    sideBar.SaveButton:SetScript("OnClick", function()
        local activeLoadout = self:GetActiveLoadout();
        if not activeLoadout or not activeLoadout.id then return; end

        self:UpdateCustomLoadoutWithCurrentTalents(activeLoadout.id);
        self:SaveButtonUpdateEnableState();
    end);
    sideBar.SaveButton.tooltipText = "Save the current talents into the currently selected loadout";

    -- add a Config button
    sideBar.ConfigButton = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.ConfigButton:SetSize((width / 2) - 10, 20);
    sideBar.ConfigButton:SetText("Config");
    sideBar.ConfigButton:SetPoint("TOPLEFT", sideBar.SaveButton, "TOPRIGHT", 0, 0);
    sideBar.ConfigButton:SetScript("OnClick", function()
        self:ShowConfigDialog();
    end);
    sideBar.ConfigButton.tooltipText = "Open the configuration UI";

    -- add a expand button
    sideBar.ToggleSideBarButton = CreateFrame("Button", nil, talentsTab, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.ToggleSideBarButton:SetSize(24, 38);
    sideBar.ToggleSideBarButton:SetFrameStrata("HIGH");
    sideBar.ToggleSideBarButton:SetNormalTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-FlyoutButton");
    sideBar.ToggleSideBarButton:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-FlyoutButton");
    sideBar.ToggleSideBarButton:GetNormalTexture():SetTexCoord(0.15625, 0.5, 0.84375, 0.5, 0.15625, 0, 0.84375, 0);
    sideBar.ToggleSideBarButton:GetHighlightTexture():SetTexCoord(0.15625, 1, 0.84375, 1, 0.15625, 0.5, 0.84375, 0.5);
    sideBar.ToggleSideBarButton:SetPoint("RIGHT", talentsTab, "TOPLEFT", 10, -52);
    sideBar.ToggleSideBarButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(sideBar.ToggleSideBarButton, "ANCHOR_RIGHT");
        GameTooltip:SetText("Toggle Sidebar");
        GameTooltip:AddLine("|cffeda55fShift + Click|r to move the side bar to the other side of the UI.", 1, 1, 1, true);
        GameTooltip:Show();
    end);
    sideBar.ToggleSideBarButton:SetScript("OnClick", function()
        self:OnToggleSideBarButtonClick();
    end);

    -- add a scrollbox frame
    local dataProvider
    sideBar.ScrollBoxContainer, dataProvider = self:CreateScrollBox(sideBar);
    sideBar.ScrollBoxContainer:SetPoint("TOPLEFT", sideBar.SaveButton, "BOTTOMLEFT", 0, -10);
    sideBar.ScrollBoxContainer:SetPoint("BOTTOMRIGHT", sideBar, "BOTTOMRIGHT", -10, 10);

    -- add a warning on the bottom of the sideBar
    sideBar.Warning = sideBar:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Large");
    sideBar.Warning:SetPoint("BOTTOMLEFT", sideBar, "BOTTOMLEFT", 10, 10);
    sideBar.Warning:SetWidth(width - 50);
    sideBar.Warning:SetText('');
    sideBar.Warning:SetTextColor(1, 0.5, 0.5);
    sideBar.Warning:SetScript("OnShow", function()
        local badAddons = ns.TLM:CheckForBadAddons(false);
        local text = "";
        for _, warning in pairs(badAddons) do
            text = text .. warning .. "\n";
        end
        sideBar.Warning:SetText(text);
    end);

    return sideBar, dataProvider;
end

function SideBarMixin:CreateScrollBox(parentContainer)
    --- @class TLM_SideBarContainerFrame : Frame
    local ContainerFrame = CreateFrame("Frame", nil, parentContainer);

    ContainerFrame.ScrollBar = CreateFrame("EventFrame", nil, ContainerFrame, "WowTrimScrollBar");
    ContainerFrame.ScrollBar:SetPoint("TOPRIGHT");
    ContainerFrame.ScrollBar:SetPoint("BOTTOMRIGHT");

    ContainerFrame.ScrollBox = CreateFrame("Frame", nil, ContainerFrame, "WowScrollBoxList");
    ContainerFrame.ScrollBox:SetPoint("TOPLEFT");
    ContainerFrame.ScrollBox:SetPoint("BOTTOMRIGHT", ContainerFrame.ScrollBar, "BOTTOMLEFT");
    --- @param frame TLM_ElementFrame
    local function elementFrameApplyColors(frame)
        local isSelected = (frame == self.activeLoadoutFrame);
        --- @type ColorType
        local textColor = isSelected
            and Config:GetConfig('sideBarActiveElementTextColor')
            or Config:GetConfig('sideBarInactiveElementTextColor');
        --- @type ColorType
        local backgroundColor = isSelected
            and Config:GetConfig('sideBarActiveElementBackgroundColor')
            or Config:GetConfig('sideBarInactiveElementBackgroundColor');
        --- @type ColorType
        local highlightBackgroundColor = isSelected
            and Config:GetConfig('sideBarActiveElementHighlightBackgroundColor')
            or Config:GetConfig('sideBarInactiveElementHighlightBackgroundColor');

        frame.Text:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a);
        frame.Background:SetColorTexture(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a);
        frame.HighlightBackground:SetColorTexture(highlightBackgroundColor.r, highlightBackgroundColor.g, highlightBackgroundColor.b, highlightBackgroundColor.a);
    end

    --- @param frame TLM_ElementFrame
    --- @param entry TLM_SideBarDataProviderEntry
    local function OnListElementInitialized(frame, entry)
        --- @class TLM_ElementFrame
        local frame = frame;
        if not frame.Background then
            frame.Background = frame:CreateTexture(nil, "BACKGROUND");
            frame.Background:SetAllPoints(frame);
        end

        if not frame.Text then
            frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
            frame.Text:SetJustifyH("LEFT");
            frame.Text:SetAllPoints(frame);
        end

        if not frame.HighlightBackground then
            frame.HighlightBackground = frame:CreateTexture(nil, "BACKGROUND");
            frame.HighlightBackground:SetAllPoints(frame);
            frame.HighlightBackground:Hide();
        end

        if entry.isActive then
            self.activeLoadoutFrame = frame;
        end
        local text = entry.text;
        if entry.data.isLocked then
            text = LOCK_MARKUP .. text;
        end
        if entry.parentID then
            text = "  ||  " .. text;
        end
        frame.Text:SetText(text);

        frame.ApplyColors = elementFrameApplyColors;
        frame:ApplyColors();

        Config:RegisterCallback(Config.Event.OptionValueChanged, function(_, option)
            if Config.sideBarColorOptionKeys[option] then
                frame:ApplyColors();
            end
        end, frame);
        frame:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then
                self:OnElementClick(frame, entry.data);
            elseif button == "RightButton" then
                self:OnElementRightClick(frame, entry.data);
            end
        end);
        frame:SetScript("OnEnter", function()
            frame.TalentBuildExportString = nil;
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
            GameTooltip:SetText(entry.data.name);
            local defaultAction = self:GetDefaultActionText(entry);
            GameTooltip:AddLine(string.format("Left-Click to %s this loadout", defaultAction), 1, 1, 1);
            GameTooltip:AddLine("Shift-Click to link to chat", 1, 1, 1);
            GameTooltip:AddLine("Right-Click for options", 1, 1, 1);

            -- Allows other addons, like TalentTreeTweaks to safely hook into GameTooltip:Show
            frame.TalentBuildExportString = GlobalAPI:GetExportString(entry.data.id);

            GameTooltip:Show();

            frame.HighlightBackground:Show();
        end);
        frame:SetScript("OnLeave", function()
            GameTooltip:Hide();

            frame.HighlightBackground:Hide();
        end);
        frame:RegisterForClicks("AnyUp");
    end

    ContainerFrame.ScrollView = CreateScrollBoxListLinearView();
    ContainerFrame.ScrollView:SetElementExtent(20);  -- Fixed height for each row; required as we"re not using XML.
    ContainerFrame.ScrollView:SetElementInitializer("Button", OnListElementInitialized);

    ScrollUtil.InitScrollBoxWithScrollBar(ContainerFrame.ScrollBox, ContainerFrame.ScrollBar, ContainerFrame.ScrollView)

    local dataProvider = CreateDataProvider();
    ContainerFrame.ScrollBox:SetDataProvider(dataProvider);

    return ContainerFrame, dataProvider;
end

--- @param rootDescription RootMenuDescriptionProxy
--- @param frame TLM_ElementFrame
--- @param loadoutInfo TLM_SideBarLoadoutInfo
function SideBarMixin:GenerateMenu(rootDescription, frame, loadoutInfo)
    local talentsTab = self:GetTalentsTab();
    local classID = talentsTab:GetClassID();
    local playerClassID = select(3, UnitClass("player"));

    rootDescription:CreateTitle(loadoutInfo.displayName);
    rootDescription:CreateButton("Load", function()
        local forceApply = false;
        self:OnElementClick(frame, loadoutInfo, forceApply);
    end);
    if self.ShowLoadAndApply then
        rootDescription:CreateButton("Load & Apply", function()
            local forceApply = true;
            self:OnElementClick(frame, loadoutInfo, forceApply);
        end);
    end
    rootDescription:CreateButton("Save current talents into loadout", function()
        self:UpdateCustomLoadoutWithCurrentTalents(loadoutInfo.id);
    end):SetEnabled(not loadoutInfo.isBlizzardLoadout and not loadoutInfo.isLocked);

    local lock = rootDescription:CreateCheckbox(
        "Locked",
        function() return loadoutInfo.isLocked; end,
        function() self:ToggleLock(loadoutInfo.id); return MenuResponse.CloseAll; end
    );
    lock:SetEnabled(not loadoutInfo.isBlizzardLoadout);
    lock:SetTitleAndTextTooltip("Lock loadout", "Locking a loadout blocks you from saving changes to it.");

    rootDescription:CreateButton("Rename", function()
        StaticPopup_Show(self.renameDialogName, loadoutInfo.name, nil, loadoutInfo);
    end):SetEnabled(loadoutInfo.playerIsOwner);
    if classID == playerClassID and not loadoutInfo.isBlizzardLoadout then
        local baseLoadoutElementDescription = rootDescription:CreateButton("Set Blizzard base loadout", function() end);

        local function isSelected(data) return data.id == loadoutInfo.parentID; end
        local function setSelected(data) CharacterAPI:SetParentLoadout(loadoutInfo.id, data.id); end
        --- @type TLM_SideBarDataProviderEntry[]
        local elements = self.DataProvider:GetCollection();
        for _, element in ipairs(elements) do
            if element.data.isBlizzardLoadout and element.data.playerIsOwner then
                baseLoadoutElementDescription:CreateRadio(element.data.displayName, isSelected, setSelected, element.data);
            end
        end
    end
    rootDescription:CreateButton("Export", function()
        self:ExportLoadout(loadoutInfo);
    end);
    rootDescription:CreateButton("Link to chat", function()
        self:LinkToChat(loadoutInfo.id);
    end);
    if self.ShowShowInTTV then
        rootDescription:CreateButton("Open in TalentTreeViewer", function()
            self:OpenInTalentTreeViewer(loadoutInfo);
        end):SetEnabled(nil ~= TalentViewerLoader);
    end
    if loadoutInfo.playerIsOwner then
        rootDescription:CreateButton("Delete", function()
            StaticPopup_Show(self.deleteDialogName, loadoutInfo.name, nil, loadoutInfo);
        end);
    else
        rootDescription:CreateButton("Remove from list", function()
            StaticPopup_Show(self.removeFromListDialogName, loadoutInfo.name, nil, loadoutInfo);
        end);
        rootDescription:CreateButton("Remove all loadouts from this character from the list", function()
            StaticPopup_Show(self.removeFromListBulkDialogName, loadoutInfo.owner, nil, loadoutInfo);
        end);
        rootDescription:CreateButton("Permanently hide all loadouts from this character", function()
            Config:SetCharacterShown(loadoutInfo.owner, false);
            TLM:Printf("Loadouts from %s are now hidden. You can reset this in the config.", loadoutInfo.owner);
        end);
    end
end

--- @param owner string
function SideBarMixin:RemoveAllLoadoutsByOwner(owner)
    local dataProvider = self.DataProvider;
    --- @type TLM_SideBarDataProviderEntry[]
    local elements = dataProvider:GetCollection();
    for _, v in pairs(elements) do
        if v.data.isBlizzardLoadout and owner == v.data.owner then
            GlobalAPI:RemoveLoadoutFromStorage(v.data.id);
        end
    end
end

function SideBarMixin:ToggleLock(loadoutID)
    local loadoutInfo = GlobalAPI:GetLoadoutInfoByID(loadoutID);
    if not loadoutInfo then return; end

    GlobalAPI:SetLoadoutLocked(loadoutID, not loadoutInfo.isLocked);
end

--- @param frame TLM_ElementFrame
--- @param loadoutInfo TLM_SideBarLoadoutInfo
function SideBarMixin:SetElementAsActive(frame, loadoutInfo)
    self.activeLoadout = loadoutInfo;
    local previouslyActiveLoadoutFrame = self.activeLoadoutFrame;
    self.activeLoadoutFrame = frame;
    if previouslyActiveLoadoutFrame then
        previouslyActiveLoadoutFrame:ApplyColors();
    end
    frame:ApplyColors();
    self:SaveButtonUpdateEnableState();
end

--- @param frame TLM_ElementFrame
--- @param loadoutInfo TLM_SideBarLoadoutInfo
function SideBarMixin:OnElementClick(frame, loadoutInfo, forceApply)
    if IsShiftKeyDown() then
        self:LinkToChat(loadoutInfo.id);
        return;
    end
    self:SetElementAsActive(frame, loadoutInfo);
    if forceApply == nil then forceApply = Config:GetConfig('autoApply') end
    local autoApply = forceApply;

    self:DoLoad(loadoutInfo.id, autoApply);
end

--- @param frame TLM_ElementFrame
--- @param loadoutInfo TLM_SideBarLoadoutInfo
function SideBarMixin:OnElementRightClick(frame, loadoutInfo)
    MenuUtil.CreateContextMenu(frame, function(_, rootDescription)
        self:GenerateMenu(rootDescription, frame, loadoutInfo);
    end);
end

function SideBarMixin:LinkToChat(loadoutId)
    local exportString = GlobalAPI:GetExportString(loadoutId);
    if not exportString then
        return;
    end

    if not TALENT_BUILD_CHAT_LINK_TEXT then
        if not ChatEdit_InsertLink(exportString) then
            ChatFrame_OpenChat(exportString);
        end
        return;
    end

    local talentsTab = self:GetTalentsTab();

    local specName = talentsTab:GetSpecName();
    local className = talentsTab:GetClassName();
    local specID = talentsTab:GetSpecID();
    local classColor = RAID_CLASS_COLORS[select(2, GetClassInfo(talentsTab:GetClassID()))];
    local level = LEVEL_CAP;

    local linkDisplayText = ("[%s]"):format(TALENT_BUILD_CHAT_LINK_TEXT:format(specName, className));
    local linkText = LinkUtil.FormatLink("talentbuild", linkDisplayText, specID, level, exportString);
    local chatLink = classColor:WrapTextInColorCode(linkText);
    if not ChatEdit_InsertLink(chatLink) then
        ChatFrame_OpenChat(chatLink);
    end
end

--- @param loadoutInfo TLM_SideBarLoadoutInfo
function SideBarMixin:ExportLoadout(loadoutInfo)
    local exportString = GlobalAPI:GetExportString(loadoutInfo.id);
    if not exportString then
        return;
    end

    StaticPopup_Show(self.copyDialogName, nil, nil, exportString);
end

--- @param loadoutInfo TLM_SideBarLoadoutInfo
function SideBarMixin:OpenInTalentTreeViewer(loadoutInfo)
    local exportString = GlobalAPI:GetExportString(loadoutInfo.id);
    if not exportString then
        return;
    end
    if TalentViewerLoader then
        TalentViewerLoader:LoadTalentViewer();
    else
        C_AddOns.LoadAddOn('TalentTreeViewer');
    end
    local TalentViewer = TalentViewerLoader:GetTalentViewer() or _G.TalentViewer;
    if not TalentViewer or not TalentViewer.ImportLoadout then
        return;
    end
    TalentViewer:ImportLoadout(exportString);
end

--- @param dataProviderEntries TLM_SideBarDataProviderEntry[]
function SideBarMixin:SortElements(dataProviderEntries)
    --- order by:
    --- 1. playerIsOwner
    --- 2. isBlizzardLoadout
    --- 3. name
    --- 4. id (basically, the order they were created)
    ---
    --- custom loadouts are listed underneath their parent, if any

    --- @param a TLM_SideBarDataProviderEntry
    --- @param b TLM_SideBarDataProviderEntry
    local function compare(a, b)
        if not b then
            return false;
        end

        if a.data.playerIsOwner and not b.data.playerIsOwner then
            return true;
        elseif not a.data.playerIsOwner and b.data.playerIsOwner then
            return false;
        end

        if a.data.isBlizzardLoadout and not b.data.isBlizzardLoadout then
            return true;
        elseif not a.data.isBlizzardLoadout and b.data.isBlizzardLoadout then
            return false;
        end

        if a.data.name < b.data.name then
            return true;
        elseif a.data.name > b.data.name then
            return false;
        end

        if a.data.id < b.data.id then
            return true;
        elseif a.data.id > b.data.id then
            return false;
        end

        return false;
    end

    --- @type TLM_SideBarDataProviderEntry[]
    local elements = CopyTable(dataProviderEntries);

    table.sort(elements, compare);
    local lookup = {};
    for index, element in ipairs(elements) do
        element.order = index; ---@diagnostic disable-line: inject-field
        element.subOrder = 0; ---@diagnostic disable-line: inject-field
        lookup[element.data.id] = element;
    end

    for index, element in ipairs(elements) do
        local parentIndex = element.parentID and lookup[element.parentID] and lookup[element.parentID].order;
        if parentIndex then
            element.order = parentIndex; ---@diagnostic disable-line: inject-field
            element.subOrder = index; ---@diagnostic disable-line: inject-field
        end
    end

    table.sort(dataProviderEntries, function(a, b)
        if not b then
            return false;
        end
        a = lookup[a.data.id];
        b = lookup[b.data.id];

        if a.order == b.order then
            return a.subOrder < b.subOrder;
        end
        return a.order < b.order;
    end);
end

function SideBarMixin:RefreshSideBarData()
    local loadouts = self:GetLoadouts();

    local previouslyActiveLoadoutFrame = self.activeLoadoutFrame;
    self.activeLoadoutFrame = nil;
    if previouslyActiveLoadoutFrame then
        previouslyActiveLoadoutFrame:ApplyColors();
    end

    self.activeLoadout = self:GetActiveLoadout(true);
    local foundActiveLoadout = false;
    local activeLoadoutID = self.activeLoadout and self.activeLoadout.id or nil;
    local dataProviderEntries = {}
    for _, loadout in pairs(loadouts) do
        if loadout.playerIsOwner or not loadout.owner or Config:IsCharacterShown(loadout.owner) then
            --- @type TLM_SideBarLoadoutInfo
            local loadout = loadout ---@diagnostic disable-line: assign-type-mismatch, redefined-local
            --- @type number?
            local parentID = loadout.parentMapping and loadout.parentMapping[0];
            loadout.parentID = parentID;
            --- @type TLM_SideBarDataProviderEntry
            local entry = {
                text = loadout.displayName,
                data = loadout,
                isActive = loadout.id == activeLoadoutID,
                parentID = parentID,
            };
            table.insert(dataProviderEntries, entry);
            if loadout.id == activeLoadoutID then
                foundActiveLoadout = true;
            end
        end
    end
    if not foundActiveLoadout then
        self.activeLoadout = nil;
    end
    self:SortElements(dataProviderEntries);
    self.DataProvider = CreateDataProvider(dataProviderEntries);
    self.SideBar.ScrollBoxContainer.ScrollBox:SetDataProvider(self.DataProvider);

    self:SaveButtonUpdateEnableState();
end

function SideBarMixin:ShowConfigDialog()
    ns.Config:OpenConfigDialog();
end

function SideBarMixin:TryIntegrateWithBlizzMove()
    if not self.IntegrateWithBlizzMove or not C_AddOns.IsAddOnLoaded('BlizzMove') then return; end

    local compatible = false;
    --- @type BlizzMoveAPI|nil
    local BlizzMoveAPI = _G.BlizzMoveAPI; ---@diagnostic disable-line: undefined-field
    if(BlizzMoveAPI and BlizzMoveAPI.GetVersion and BlizzMoveAPI.RegisterAddOnFrames) then
        local _, _, _, _, versionInt = BlizzMoveAPI:GetVersion()
        if (versionInt == nil or versionInt >= 30200) then
            compatible = true;
        end
    end

    if(not compatible) then
        print(addonName .. ' is not compatible with the current version of BlizzMove, please update.')
        return;
    end
    if not BlizzMoveAPI then return end

    local frameTable = self:GetBlizzMoveFrameTable();
    BlizzMoveAPI:RegisterAddOnFrames(frameTable);
end

function SideBarMixin:TryShowLoadoutCompleteAnimation()
    local talentsTab = self:GetTalentsTab();
    if talentsTab:IsShown() and talentsTab.SetCommitCompleteVisualsActive then
        talentsTab:SetCommitCompleteVisualsActive(true);
    end
end
