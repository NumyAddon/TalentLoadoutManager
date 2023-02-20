local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;

local Module = TLM:NewModule("SideBar", "AceHook-3.0");
TLM.SideBarModule = Module;

--- @type LibUIDropDownMenu
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0");

--- @type TalentLoadoutManagerConfig
local Config = ns.Config;

--- @type TalentLoadoutManagerAPI
local API = TalentLoadoutManagerAPI;
local GlobalAPI = TalentLoadoutManagerAPI.GlobalAPI;
local CharacterAPI = TalentLoadoutManagerAPI.CharacterAPI;

function Module:OnInitialize()
    self.renameDialogName = "TalentLoadoutManager_SideBar_RenameLoadout";
    StaticPopupDialogs[self.renameDialogName] = {
        text = "Rename loadout (%s)",
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        OnShow = function (dialog, data)
            dialog.editBox:SetText(data.name);
            dialog.editBox:HighlightText();
            dialog.editBox:SetScript("OnEscapePressed", function()
                dialog:Hide();
            end);
            dialog.editBox:SetScript("OnEnterPressed", function()
                dialog.button1:Click();
            end);
        end,
        OnAccept = function(dialog, data)
            local newName = dialog.editBox:GetText();
            GlobalAPI:RenameLoadout(data.id, newName);
            dialog:Hide();
        end,
        EditBoxOnTextChanged = function (self)
            if self:GetText() == "" then
                self:GetParent().button1:Disable();
            else
                self:GetParent().button1:Enable();
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.createDialogName = "TalentLoadoutManager_SideBar_CreateLoadout";
    StaticPopupDialogs[self.createDialogName] = {
        text = "Create custom loadout",
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        OnShow = function (dialog)
            dialog.editBox:SetScript("OnEscapePressed", function()
                dialog:Hide();
            end);
            dialog.editBox:SetScript("OnEnterPressed", function()
                dialog.button1:Click();
            end);
        end,
        OnAccept = function(dialog)
            local name = dialog.editBox:GetText();
            CharacterAPI:CreateCustomLoadoutFromCurrentTalents(name);
            dialog:Hide();
        end,
        EditBoxOnTextChanged = function (self)
            if self:GetText() == "" then
                self:GetParent().button1:Disable();
            else
                self:GetParent().button1:Enable();
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.deleteDialogName = "TalentLoadoutManager_SideBar_DeleteLoadout";
    StaticPopupDialogs[self.deleteDialogName] = {
        text = "Delete loadout (%s)?",
        button1 = OKAY,
        button2 = CANCEL,
        OnAccept = function(dialog, data)
            GlobalAPI:DeleteLoadout(data.id);
            dialog:Hide();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.copyDialogName = "TalentLoadoutManager_SideBar_CopyText";
    StaticPopupDialogs[self.copyDialogName] = {
        text = "CTRL-C to copy",
        button1 = CLOSE,
        OnShow = function(dialog, data)
            local function HidePopup()
                dialog:Hide();
            end
            dialog.editBox:SetScript("OnEscapePressed", HidePopup);
            dialog.editBox:SetScript("OnEnterPressed", HidePopup);
            dialog.editBox:SetScript("OnKeyUp", function(_, key)
                if IsControlKeyDown() and key == "C" then
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

    self.genericPopupDialogName = "TalentLoadoutManager_SideBar_GenericPopup";
    StaticPopupDialogs[self.genericPopupDialogName] = {
        text = "%s",
        button1 = OKAY,
        button2 = nil,
        timeout = 0,
        OnAccept = function()
        end,
        OnCancel = function()
        end,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };
end

function Module:OnEnable()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_ClassTalentUI", function()
        self:SetupHook();
    end);
end

function Module:OnDisable()
    self:UnhookAll();

    API:UnregisterCallback(API.Event.LoadoutListUpdated, self);
    API:UnregisterCallback(API.Event.CustomLoadoutApplied, self);
end

function Module:SetupHook()
    if not self.SideBar then
        self.SideBar, self.DataProvider = self:CreateSideBar();
        self.DropDown = self:InitDropDown(self.SideBar);
        self:TryIntegrateWithBlizzMove();
    end
    if not self.importDialog then
        self.importDialog = self:CreateImportDialog();
    end
    self:SecureHookScript(ClassTalentFrame.TalentsTab, "OnShow", "OnTalentsTabShow");

    API:RegisterCallback(API.Event.LoadoutListUpdated, self.RefreshSideBarData, self);
    API:RegisterCallback(API.Event.CustomLoadoutApplied, self.RefreshSideBarData, self);
end

function Module:OnTalentsTabShow(frame)
    self:UpdateScaleForFit(frame:GetParent());
    self:UpdatePosition(frame:GetParent());
    self:RefreshSideBarData();
end

function Module:UpdateScaleForFit(frame)
    if not Config:GetConfig('autoScale') then return end

    local extraHeight = 270;
    local extraWidth = 200 + (self.SideBar:GetWidth() * 1.5);

    local horizRatio = UIParent:GetWidth() / GetUIPanelWidth(frame, extraWidth);
    local vertRatio = UIParent:GetHeight() / GetUIPanelHeight(frame, extraHeight);

    frame:SetScale(min(horizRatio, vertRatio, 1));
end

function Module:UpdatePosition(frame)
    if not Config:GetConfig('autoPosition') then return end

    local replacePoint = true;
    local yOfs = -41;
    if frame:GetNumPoints() > 0 then
        local point, relativeTo, relativePoint, xOfs;
        point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1);
        replacePoint = false;
        if point == "TOP" and relativeTo == UIParent and relativePoint == "TOP" and xOfs == 0 then
            replacePoint = true;
        end
    end

    if replacePoint then
        frame:ClearAllPoints();
        frame:SetPoint("TOP", UIParent, "TOP", self.SideBar:GetWidth() / 2, yOfs);
    end
end

function Module:CreateImportDialog()
    --- main dialog
    local dialog = CreateFrame("Frame", nil, UIParent, "ClassTalentLoadoutDialogTemplate");
    dialog.titleText = "Import Custom Loadout";
    Mixin(dialog, ClassTalentLoadoutImportDialogMixin);
    dialog:SetSize(460, 300);
    dialog:Hide();

    --- import control
    dialog.ImportControl = CreateFrame("Frame", nil, dialog);
    local importControl = dialog.ImportControl;
    importControl.labelText = HUD_CLASS_TALENTS_IMPORT_DIALOG_EDIT_BOX_LABEL;
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
    nameControl:SetPoint("TOPLEFT", importControl, "BOTTOMLEFT", 0, -25);
    nameControl:SetPoint("TOPRIGHT", importControl, "BOTTOMRIGHT", 0, -25);
    Mixin(nameControl, ClassTalentLoadoutImportDialogNameControlMixin);

    nameControl:OnLoad();
    nameControl:SetScript("OnShow", nameControl.OnShow);

    --- autoApply checkbox
    dialog.AutoApplyCheckbox = CreateFrame('CheckButton', nil, dialog, 'UICheckButtonTemplate');
    local checkbox = dialog.AutoApplyCheckbox;
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

    -- ImportIntoCurrentLoadout checkbox
    dialog.ImportIntoCurrentLoadoutCheckbox = CreateFrame('CheckButton', nil, dialog, 'UICheckButtonTemplate');
    checkbox = dialog.ImportIntoCurrentLoadoutCheckbox;
    checkbox:SetPoint('TOPLEFT', dialog.AutoApplyCheckbox, 'BOTTOMLEFT', 0, 5);
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

    function dialog:OnAccept()
        if self.AcceptButton:IsEnabled() then
            local importText = self.ImportControl:GetText();
            local loadoutName = self.NameControl:GetText();
            local autoApply = self.AutoApplyCheckbox:GetChecked();
            local importIntoCurrentLoadout = self.ImportIntoCurrentLoadoutCheckbox:IsShown() and self.ImportIntoCurrentLoadoutCheckbox:GetChecked();

            local result, errorOrNil;
            if not importIntoCurrentLoadout then
                result, errorOrNil = CharacterAPI:ImportCustomLoadout(importText, loadoutName, autoApply);
            else
                result, errorOrNil = GlobalAPI:UpdateCustomLoadoutWithImportString(Module.activeLoadout.id, importText);
                if autoApply and result and not errorOrNil then
                    CharacterAPI:LoadLoadout(Module.activeLoadout.id, autoApply);
                end
            end

            if result then
                StaticPopupSpecial_Hide(self);
            elseif errorOrNil then
                StaticPopup_Show(Module.genericPopupDialogName, ERROR_COLOR:WrapTextInColorCode(errorOrNil));
            end
        end
    end

    dialog:OnLoad();
    dialog:SetScript("OnShow", function()
        dialog.ImportIntoCurrentLoadoutCheckbox:SetShown(not self.activeLoadout.isBlizzardLoadout);
        dialog.AutoApplyCheckbox:SetChecked(Config:GetConfig('autoApply'));
    end);
    dialog:SetScript("OnHide", dialog.OnHide);

    return dialog;
end

function Module:CreateSideBar()
    local sideBar = CreateFrame("Frame", nil, ClassTalentFrame.TalentsTab);
    local width = 300;

    sideBar:SetHeight(ClassTalentFrame.TalentsTab:GetHeight());
    sideBar:SetWidth(width);
    sideBar:SetPoint("TOPRIGHT", ClassTalentFrame.TalentsTab, "TOPLEFT", 0, 0);

    -- add a background
    sideBar.Background = sideBar:CreateTexture(nil, "BACKGROUND");
    sideBar.Background:SetAllPoints();
    sideBar.Background:SetColorTexture(0, 0, 0, 0.8);

    -- add a title
    sideBar.Title = sideBar:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    sideBar.Title:SetPoint("TOPLEFT", sideBar, "TOPLEFT", 10, -10);
    sideBar.Title:SetText("Talent Loadout Manager (BETA)");

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
        self:SaveCurrentTalentsIntoLoadout();
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

    -- add a scrollbox frame
    local dataProvider
    sideBar.ScrollBox, dataProvider = self:CreateScrollBox(sideBar);
    sideBar.ScrollBox:SetPoint("TOPLEFT", sideBar.SaveButton, "BOTTOMLEFT", 0, -10);
    sideBar.ScrollBox:SetPoint("BOTTOMRIGHT", sideBar, "BOTTOMRIGHT", -10, 10);

    if not IsAddOnLoaded('TalentTreeTweaks') then
        -- add a link to the addon
        sideBar.WarningLink = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
        sideBar.WarningLink:SetSize(width - 50, 20);
        sideBar.WarningLink:SetText("Download TalentTreeTweaks");
        sideBar.WarningLink:SetPoint("BOTTOMLEFT", sideBar, "BOTTOMLEFT", 10, 10);
        sideBar.WarningLink:SetScript("OnClick", function()
            local url = "https://www.curseforge.com/wow/addons/talent-tree-tweaks";
            StaticPopup_Show(self.copyDialogName, nil, nil, url);
        end);

        -- add a warning on the bottom of the sidebar
        sideBar.Warning = sideBar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge");
        sideBar.Warning:SetPoint("BOTTOMLEFT", sideBar.WarningLink, "TOPLEFT", 0, 0);
        sideBar.Warning:SetWidth(width - 50);
        sideBar.Warning:SetText("TalentTreeTweaks is not loaded. You might encounter serious bugs without it.");
        sideBar.Warning:SetTextColor(1, 0.5, 0.5);

        local function onOptionChange(_, option, value)
            if option == 'disableTTTWarning' then
                sideBar.Warning:SetShown(not value);
                sideBar.WarningLink:SetShown(not value);
            end
        end
        Config:RegisterCallback(Config.Event.OptionValueChanged, onOptionChange);
        onOptionChange(nil, 'disableTTTWarning', Config:GetConfig('disableTTTWarning'));
    end

    return sideBar, dataProvider;
end

function Module:CreateScrollBox(parentContainer)
    local ContainerFrame = CreateFrame("Frame", nil, parentContainer);

    ContainerFrame.ScrollBar = CreateFrame("EventFrame", nil, ContainerFrame, "WowTrimScrollBar");
    ContainerFrame.ScrollBar:SetPoint("TOPRIGHT");
    ContainerFrame.ScrollBar:SetPoint("BOTTOMRIGHT");

    ContainerFrame.ScrollBox = CreateFrame("Frame", nil, ContainerFrame, "WowScrollBoxList");
    ContainerFrame.ScrollBox:SetPoint("TOPLEFT");
    ContainerFrame.ScrollBox:SetPoint("BOTTOMRIGHT", ContainerFrame.ScrollBar, "BOTTOMLEFT");

    local function OnListElementInitialized(frame, elementData)
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
            frame.HighlightBackground:SetColorTexture(0.5, 0.5, 0.5, 0.5);
            frame.HighlightBackground:Hide();
        end

        frame.Background:SetColorTexture(0, 0, 0, 0.5);
        if elementData.isActive then
            frame.Background:SetColorTexture(0.2, 0.2, 0.2, 0.5);
        end
        frame.Text:SetText(elementData.text);

        frame:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then
                self:OnElementClick(elementData.data);
            elseif button == "RightButton" then
                self:OnElementRightClick(frame, elementData.data);
            end
        end);
        frame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
            GameTooltip:SetText(elementData.text);
            local defaultAction =
                (elementData.data.playerIsOwner and elementData.data.isBlizzardLoadout) and "load & apply"
                or Config:GetConfig('autoApply') and "load & apply"
                or "load";
            GameTooltip:AddLine(string.format("Left-Click to %s this loadout", defaultAction), 1, 1, 1);
            GameTooltip:AddLine("Right-Click for options", 1, 1, 1);
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

    local dataProvider = CreateDataProvider()
    dataProvider:SetSortComparator(function(a, b) return self:SortElements(a, b) end, true);
    ContainerFrame.ScrollBox:SetDataProvider(dataProvider)

    return ContainerFrame, dataProvider;
end

function Module:InitDropDown(parentFrame)
    local dropDown = LibDD:Create_UIDropDownMenu("TalentLoadoutManager_SideBar_DropDown", parentFrame);
    return dropDown;
end

function Module:OpenDropDownMenu(dropDown, frame, elementData)
    --- title (name of the loadout)
    --- apply action (load the loadout)
    --- rename action (rename the loadout, disabled if blizzard)
    --- export action (export the loadout)
    --- view in TalentTreeViewer (if loaded)
    --- delete action (delete the loadout, disabled if blizzard)

    self.menuList = {
        {
            text = elementData.displayName,
            isTitle = true,
            notCheckable = true,
        },
        {
            text = "Load",
            notCheckable = true,
            func = function()
                local forceApply = false;
                self:OnElementClick(elementData, forceApply);
            end,
        },
        {
            text = "Load & Apply",
            notCheckable = true,
            func = function()
                local forceApply = true;
                self:OnElementClick(elementData, forceApply);
            end,
        },
        {
            text = "Save current talents into loadout",
            notCheckable = true,
            disabled = elementData.isBlizzardLoadout,
            func = function()
                CharacterAPI:UpdateCustomLoadoutWithCurrentTalents(elementData.id);
            end,
        },
        {
            text = "Rename",
            notCheckable = true,
            disabled = not elementData.playerIsOwner,
            func = function()
                StaticPopup_Show(self.renameDialogName, elementData.displayName, nil, elementData);
            end,
        },
        {
            text = "Export",
            notCheckable = true,
            func = function()
                self:ExportLoadout(elementData);
            end,
        },
        {
            text = "Open in TalentTreeViewer",
            notCheckable = true,
            disabled = not (GetAddOnEnableState(UnitName('player'), 'TalentTreeViewer') == 2),
            func = function()
                self:OpenInTalentTreeViewer(elementData);
            end,
        },
        {
            text = "Delete",
            notCheckable = true,
            disabled = not elementData.playerIsOwner,
            func = function()
                StaticPopup_Show(self.deleteDialogName, elementData.displayName, nil, elementData);
            end,
        }
    };

    LibDD:EasyMenu(self.menuList, dropDown, frame, 80, 0);
end

function Module:OnElementClick(elementData, forceApply)
    if forceApply == nil then forceApply = Config:GetConfig('autoApply') end
    local autoApply = forceApply;

    CharacterAPI:LoadLoadout(elementData.id, autoApply);
end

function Module:OnElementRightClick(frame, elementData)
    local dropDown = self.DropDown;
    if dropDown.currentElement ~= elementData.id then
        LibDD:CloseDropDownMenus();
    end
    dropDown.currentElement = elementData.id;
    self:OpenDropDownMenu(dropDown, frame, elementData);
end

function Module:ExportLoadout(elementData)
    local exportString = GlobalAPI:GetExportString(elementData.id);
    if not exportString then
        return;
    end

    StaticPopup_Show(self.copyDialogName, nil, nil, exportString);
end

function Module:OpenInTalentTreeViewer(elementData)
    local exportString = GlobalAPI:GetExportString(elementData.id);
    if not exportString then
        return;
    end
    LoadAddOn('TalentTreeViewer');
    if not TalentViewer or not TalentViewer.ImportLoadout then
        return;
    end
    TalentViewer:ImportLoadout(exportString);
end

function Module:SortElements(a, b)
    --- order by:
    --- 1. playerIsOwner
    --- 2. isBlizzardLoadout
    --- 3. name (todo: make this optional?)
    --- 4. id (basically, the order they were created?)

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

    if a.data.displayName < b.data.displayName then
        return true;
    elseif a.data.displayName > b.data.displayName then
        return false;
    end

    if a.data.id < b.data.id then
        return true;
    elseif a.data.id > b.data.id then
        return false;
    end

    return false;
end

function Module:RefreshSideBarData()
    local dataProvider = self.DataProvider;
    dataProvider:Flush();

    local loadouts = GlobalAPI:GetLoadouts();
    self.activeLoadout = CharacterAPI:GetActiveLoadoutInfo();
    local activeLoadoutID = self.activeLoadout and self.activeLoadout.id or nil;
    for _, loadout in pairs(loadouts) do
        dataProvider:Insert({
            text = loadout.displayName,
            data = loadout,
            isActive = loadout.id == activeLoadoutID,
        });
    end

    self.SideBar.SaveButton:SetEnabled(self.activeLoadout and not self.activeLoadout.isBlizzardLoadout);
end

function Module:SaveCurrentTalentsIntoLoadout()
    if not self.activeLoadout then
        return;
    end
    CharacterAPI:UpdateCustomLoadoutWithCurrentTalents(self.activeLoadout.id);
end

function Module:ShowConfigDialog()
    ns.Config:OpenConfigDialog();
end

function Module:TryIntegrateWithBlizzMove()
    if not IsAddOnLoaded('BlizzMove') then return; end

    local compatible = false;
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
    local frameTable = {
        ["Blizzard_ClassTalentUI"] = {
            ["ClassTalentFrame"] =
            {
                MinVersion = 100000,
                SubFrames =
                {
                    ["ClassTalentFrame.TalentsTab.ButtonsParent"] =
                    {
                        MinVersion = 100000,
                    },
                    ["ClassTalentFrame.TalentsTab"] =
                    {
                        MinVersion = 100000,
                        SubFrames =
                        {
                            ["TLM-SideBar"] =
                            {
                                MinVersion = 100000,
                                FrameReference = self.SideBar,
                                Detachable = true,
                            },
                        },
                    },
                },
            },
        },
    };
    BlizzMoveAPI:RegisterAddOnFrames(frameTable);
end
