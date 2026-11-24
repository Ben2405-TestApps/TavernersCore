local Core = _G.TavernersCore
if not Core then return end

local UI = {rows={}}
Core.Settings.UI = UI
local frame, contentFrame

local function ClearRows()
  for _, row in ipairs(UI.rows) do row:Hide(); row:SetParent(nil) end
  UI.rows = {}
end

local function Build()
  if frame then return end
  frame = CreateFrame("Frame","TavernersSettingsFrame",UIParent)
  frame:SetSize(620,500); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart",frame.StartMoving); frame:SetScript("OnDragStop",frame.StopMovingOrSizing)
  if frame.SetBackdrop then
    frame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    frame:SetBackdropColor(.07,.05,.035,.97)
  end
  local title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
  title:SetPoint("TOPLEFT",18,-16); title:SetText("|cffffd27aThe Taverners|r — Shared Settings")
  local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-4,-4)
  local scroll=CreateFrame("ScrollFrame","TavernersSettingsScroll",frame,"UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",18,-48); scroll:SetPoint("BOTTOMRIGHT",-36,18)
  contentFrame=CreateFrame("Frame",nil,scroll); contentFrame:SetSize(550,400); scroll:SetScrollChild(contentFrame)
end

function UI:Refresh()
  Build(); ClearRows()
  local y=-8
  local modules={}
  for name in pairs(Core.Settings.registry or {}) do modules[#modules+1]=name end
  table.sort(modules)
  for _,moduleName in ipairs(modules) do
    local entry=Core.Settings.registry[moduleName]
    local header=contentFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    header:SetPoint("TOPLEFT",8,y); header:SetText(string.upper(moduleName))
    self.rows[#self.rows+1]=header; y=y-26
    local keys={}
    for key in pairs(entry.definitions or {}) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
      local definition=entry.definitions[key]
      local label=definition.label or key
      if definition.type=="boolean" then
        local check=CreateFrame("CheckButton",nil,contentFrame,"UICheckButtonTemplate")
        check:SetPoint("TOPLEFT",6,y); check:SetSize(24,24); check:SetChecked(entry.db[key] and true or false)
        local text=check:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        text:SetPoint("LEFT",check,"RIGHT",4,0); text:SetText(label)
        check:SetScript("OnClick",function(button) Core.Settings:Set(moduleName,key,button:GetChecked() and true or false) end)
        self.rows[#self.rows+1]=check; self.rows[#self.rows+1]=text
      elseif definition.type=="number" then
        local text=contentFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        text:SetPoint("TOPLEFT",12,y-3); text:SetText(label)
        self.rows[#self.rows+1]=text
        local input=CreateFrame("EditBox",nil,contentFrame,"InputBoxTemplate")
        input:SetSize(64,22); input:SetPoint("LEFT",text,"RIGHT",12,0); input:SetAutoFocus(false)
        input:SetText(tostring(entry.db[key] or definition.default or 0))
        input:SetScript("OnEnterPressed",function(box)
          local value=tonumber(box:GetText())
          if value then
            if definition.min then value=math.max(definition.min,value) end
            if definition.max then value=math.min(definition.max,value) end
            Core.Settings:Set(moduleName,key,value); box:SetText(tostring(value))
          else box:SetText(tostring(entry.db[key] or 0)) end
          box:ClearFocus()
        end)
        self.rows[#self.rows+1]=input
      end
      y=y-30
    end
    y=y-8
  end
  if #modules==0 then
    local empty=contentFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    empty:SetPoint("TOPLEFT",10,y); empty:SetText("No Taverners modules have registered settings yet.")
    self.rows[#self.rows+1]=empty
  end
  contentFrame:SetHeight(math.max(350,-y+20))
end

function UI:Toggle()
  Build()
  if frame:IsShown() then frame:Hide() else frame:Show(); self:Refresh() end
end

SLASH_TAVERNERSSETTINGS1="/tsettings"
SlashCmdList=SlashCmdList or {}
SlashCmdList.TAVERNERSSETTINGS=function() UI:Toggle() end
