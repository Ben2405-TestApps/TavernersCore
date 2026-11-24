-- Taverners Core - in-game diagnostics
-- Local-only diagnostics; no character or system data is transmitted.

local Core = _G.TavernersCore
if not Core then return end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

local function AddLine(lines, text)
  lines[#lines + 1] = tostring(text or "")
end

local function GetAddonInfo(index)
  if C_AddOns and C_AddOns.GetAddOnInfo then
    local name, title, notes, loadable, reason, security, newVersion = SafeCall(C_AddOns.GetAddOnInfo, index)
    return name, title, loadable, reason
  end
  if GetAddOnInfo then
    local name, title, notes, loadable, reason = SafeCall(GetAddOnInfo, index)
    return name, title, loadable, reason
  end
end

local function IsLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return SafeCall(C_AddOns.IsAddOnLoaded, name) and true or false
  end
  return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
end

local function GetDependencies(index)
  if C_AddOns and C_AddOns.GetAddOnDependencies then
    return {SafeCall(C_AddOns.GetAddOnDependencies, index)}
  end
  if GetAddOnDependencies then
    return {SafeCall(GetAddOnDependencies, index)}
  end
  return {}
end

function Core.Diagnostics:CheckDependencies()
  local report = {checked = 0, missing = {}, dependents = {}, addons = {}}
  local count = (C_AddOns and C_AddOns.GetNumAddOns and SafeCall(C_AddOns.GetNumAddOns)) or (GetNumAddOns and GetNumAddOns()) or 0
  for i = 1, count do
    local name, title, loadable, reason = GetAddonInfo(i)
    if name then
      local deps = GetDependencies(i)
      local usesCore = false
      local missingForAddon = {}
      for _, dependency in ipairs(deps) do
        if dependency then
          if dependency == "TavernersCore" then usesCore = true end
          if not IsLoaded(dependency) then
            missingForAddon[#missingForAddon + 1] = dependency
          end
        end
      end
      if usesCore then
        report.dependents[#report.dependents + 1] = {
          name = name, title = title or name, loaded = IsLoaded(name),
          missing = missingForAddon, loadable = loadable, reason = reason
        }
      end
      for _, dependency in ipairs(missingForAddon) do
        report.missing[#report.missing + 1] = name .. " requires " .. dependency
      end
      report.checked = report.checked + 1
    end
  end
  report.addons = report.dependents
  return report
end

function Core.Diagnostics:BuildText()
  local lines = {}
  local player = Core.Identity:GetPlayer()
  local deps = self:CheckDependencies()
  AddLine(lines, "TAVERNERS CORE - DIAGNOSTICS")
  AddLine(lines, "========================================")
  AddLine(lines, "Core version: " .. tostring(Core.version))
  AddLine(lines, "Protocol: " .. tostring(Core.protocolVersion))
  AddLine(lines, "Core loaded: " .. (Core.loaded and "YES" or "NO"))
  AddLine(lines, "Game build: " .. tostring((GetBuildInfo and select(2, GetBuildInfo())) or "Unavailable"))
  AddLine(lines, "Character: " .. tostring(player.name) .. " (" .. tostring(player.realm) .. ")")
  AddLine(lines, "Class: " .. tostring(player.class or "Unknown"))
  AddLine(lines, "Guild: " .. ((IsInGuild and IsInGuild()) and "Joined" or "Not in a guild"))
  AddLine(lines, "")
  AddLine(lines, "DEPENDENCY CHECK")
  AddLine(lines, "----------------------------------------")
  AddLine(lines, "Addons scanned: " .. tostring(deps.checked))
  AddLine(lines, "Taverners Core dependents: " .. tostring(#deps.dependents))
  if #deps.dependents == 0 then AddLine(lines, "No enabled/installed addons declaring TavernersCore were found.") end
  for _, addon in ipairs(deps.dependents) do
    local status = addon.loaded and "LOADED" or "NOT LOADED"
    AddLine(lines, (addon.title or addon.name) .. " [" .. status .. "]")
    if #addon.missing > 0 then
      for _, missing in ipairs(addon.missing) do AddLine(lines, "  MISSING: " .. missing) end
    elseif not addon.loaded then
      AddLine(lines, "  Check the AddOns list and any load-on-demand setting.")
    else
      AddLine(lines, "  Dependencies OK")
    end
  end
  if #deps.missing > 0 then
    AddLine(lines, "")
    AddLine(lines, "Missing dependencies:")
    for _, missing in ipairs(deps.missing) do AddLine(lines, "  " .. missing) end
  else
    AddLine(lines, "Missing dependencies: none detected")
  end
  AddLine(lines, "")
  AddLine(lines, "COMMUNICATION")
  AddLine(lines, "----------------------------------------")
  local prefixCount = 0
  for prefix in pairs(Core.Comm.prefixes or {}) do
    prefixCount = prefixCount + 1
    AddLine(lines, "Registered: " .. tostring(prefix))
  end
  AddLine(lines, "Registered prefixes: " .. tostring(prefixCount))
  AddLine(lines, "Queued messages: " .. tostring(#(Core.Comm.queue or {})))
  AddLine(lines, "")
  AddLine(lines, "REGISTERED MODULES")
  AddLine(lines, "----------------------------------------")
  local moduleCount = 0
  for name in pairs(Core.modules or {}) do moduleCount = moduleCount + 1; AddLine(lines, name) end
  if moduleCount == 0 then AddLine(lines, "No modules registered yet.") end
  AddLine(lines, "")
  AddLine(lines, "RECENT DIAGNOSTIC LOG")
  AddLine(lines, "----------------------------------------")
  local entries = self.entries or {}
  local first = math.max(1, #entries - 11)
  if #entries == 0 then AddLine(lines, "No diagnostic entries recorded.") end
  for i = first, #entries do
    local entry = entries[i]
    AddLine(lines, date and date("%H:%M:%S", entry.time) or tostring(entry.time)
      .. " [" .. tostring(entry.level) .. "] " .. tostring(entry.message))
  end
  AddLine(lines, "")
  AddLine(lines, "This report is local to this character and is not uploaded.")
  return table.concat(lines, "\n")
end

local window
local reportText
local function RefreshWindow()
  if reportText then reportText:SetText(Core.Diagnostics:BuildText()) end
end

local function CreateWindow()
  if window then return window end
  window = CreateFrame("Frame", "TavernersCoreDiagnosticsFrame", UIParent)
  window:SetSize(590, 500)
  window:SetPoint("CENTER")
  window:SetFrameStrata("DIALOG")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  if window.SetBackdrop then
    window:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    window:SetBackdropColor(0.08, 0.055, 0.035, 0.97)
  end

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 18, -15)
  title:SetText("|cffffd27aTaverners Core|r - Diagnostics")

  local subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
  subtitle:SetText("Dependency checker, addon status and local diagnostic log")

  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local refresh = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  refresh:SetSize(100, 24)
  refresh:SetPoint("BOTTOMLEFT", 16, 14)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", RefreshWindow)

  local logging = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  logging:SetSize(130, 24)
  logging:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
  logging:SetText("Toggle logging")
  logging:SetScript("OnClick", function()
    Core.Diagnostics:Enable(not Core.Diagnostics.enabled)
    Core.Notifications:Print("Verbose diagnostics " .. (Core.Diagnostics.enabled and "enabled." or "disabled."))
    RefreshWindow()
  end)

  local scroll = CreateFrame("ScrollFrame", "TavernersCoreDiagnosticsScroll", window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -58)
  scroll:SetPoint("BOTTOMRIGHT", -34, 48)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(520, 1)
  scroll:SetScrollChild(content)
  reportText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  reportText:SetPoint("TOPLEFT", 0, 0)
  reportText:SetWidth(510)
  reportText:SetJustifyH("LEFT")
  reportText:SetJustifyV("TOP")
  reportText:SetSpacing(2)
  reportText:SetText("")
  reportText:SetWordWrap(true)
  reportText:SetNonSpaceWrap(true)
  return window
end

function Core.Diagnostics:Show()
  local frame = CreateWindow()
  RefreshWindow()
  frame:Show()
end

SLASH_TAVERNERSCOREDIAGNOSTICS1 = "/tcore"
SLASH_TAVERNERSCOREDIAGNOSTICS2 = "/tavdiagnostics"
SlashCmdList = SlashCmdList or {}
SlashCmdList.TAVERNERSCOREDIAGNOSTICS = function()
  Core.Diagnostics:Show()
end

Core.Diagnostics:Log("INFO", "Diagnostics interface initialised.")
