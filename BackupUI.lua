-- Taverners Core - portable SavedVariables backup and restore.
-- Import is parsed as data only; it never executes Lua or loadstring content.
local Core = _G.TavernersCore
if not Core then return end

local BackupUI = {}
Core.Backup.UI = BackupUI

local function Encode(value)
  return tostring(value or ""):gsub("([^%w%-%_%.~])", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end)
end

local function Decode(value)
  return tostring(value or ""):gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
end

local function Split(value, separator)
  local out = {}
  separator = separator or "|"
  for part in (tostring(value or "") .. separator):gmatch("(.-)" .. separator) do
    out[#out + 1] = part
  end
  return out
end

local function KeyToken(key)
  local kind = type(key)
  if kind == "string" then return "s:" .. Encode(key) end
  if kind == "number" then return "n:" .. tostring(key) end
  if kind == "boolean" then return "b:" .. (key and "1" or "0") end
end

local function ReadKey(token)
  local kind, value = token:match("^([snb]):(.*)$")
  if kind == "s" then return Decode(value) end
  if kind == "n" then
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
  end
  if kind == "b" then
    if value == "1" then return true end
    if value == "0" then return false end
  end
  return nil
end

local function FlattenStore(storeName, value, lines, path, seen, depth)
  if depth > 20 then return false, "Backup nesting exceeds 20 levels." end
  if type(value) ~= "table" then return false, "A registered store is not a table." end
  if seen[value] then return false, "A cyclic SavedVariables table cannot be exported." end
  seen[value] = true
  local prefix = "T|" .. Encode(storeName) .. "|" .. table.concat(path, "/") .. "|"
  if #path == 0 or next(value) == nil then lines[#lines + 1] = prefix .. "T|" end
  for key, child in pairs(value) do
    local token = KeyToken(key)
    if token then
      path[#path + 1] = token
      local kind, encoded
      if type(child) == "table" then
        local ok, err = FlattenStore(storeName, child, lines, path, seen, depth + 1)
        if not ok then return false, err end
      elseif type(child) == "string" then
        kind, encoded = "S", Encode(child)
      elseif type(child) == "number" and child == child and child ~= math.huge and child ~= -math.huge then
        kind, encoded = "N", tostring(child)
      elseif type(child) == "boolean" then
        kind, encoded = "B", child and "1" or "0"
      end
      if kind then lines[#lines + 1] = "T|" .. Encode(storeName) .. "|" .. table.concat(path, "/") .. "|" .. kind .. "|" .. encoded end
      path[#path] = nil
    end
    if #lines > 10000 then return false, "Backup contains too many records." end
  end
  seen[value] = nil
  return true
end

function Core.Backup:ExportText()
  local snapshot = self:CreateSnapshot()
  local lines = {"TAVERNERS-BACKUP|1", "CREATED|" .. tostring(snapshot.created or 0), "PROTOCOL|" .. tostring(snapshot.protocol or 1)}
  local names = {}
  for name in pairs(snapshot.stores or {}) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local ok, err = FlattenStore(name, snapshot.stores[name], lines, {}, {}, 0)
    if not ok then return nil, err end
  end
  local result = table.concat(lines, "\n")
  if #result > 250000 then return nil, "Backup exceeds the 250 KB safety limit." end
  return result
end

function Core.Backup:ParseText(source)
  if type(source) ~= "string" or #source == 0 or #source > 250000 then
    return nil, "Backup text is empty or exceeds the 250 KB safety limit."
  end
  local lines = Split(source, "\n")
  if lines[1] ~= "TAVERNERS-BACKUP|1" then return nil, "Unrecognised Taverners backup format." end
  local created = tonumber((lines[2] or ""):match("^CREATED|(%d+)$")) or 0
  local protocol = tonumber((lines[3] or ""):match("^PROTOCOL|(%d+)$")) or 1
  local snapshot = {created=created, protocol=protocol, stores={}}
  local count = 0
  for index = 4, #lines do
    local storeToken, pathText, kind, value = lines[index]:match("^T|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if not storeToken then return nil, "Invalid backup record on line " .. index .. "." end
    local storeName = Decode(storeToken)
    if storeName == "" then return nil, "Backup contains an empty store name." end
    local path = {}
    if pathText ~= "" then
      for _, token in ipairs(Split(pathText, "/")) do
        local key = ReadKey(token)
        if key == nil then return nil, "Invalid table key on line " .. index .. "." end
        path[#path + 1] = key
      end
    end
    local root = snapshot.stores[storeName]
    if not root then root = {}; snapshot.stores[storeName] = root end
    local target = root
    for p = 1, #path - 1 do
      local key = path[p]
      if type(target[key]) ~= "table" then target[key] = {} end
      target = target[key]
    end
    local key = path[#path]
    if #path == 0 then
      if kind ~= "T" then return nil, "Invalid root record on line " .. index .. "." end
    elseif kind == "T" then
      if target[key] ~= nil and type(target[key]) ~= "table" then return nil, "Conflicting record on line " .. index .. "." end
      target[key] = target[key] or {}
    elseif kind == "S" then target[key] = Decode(value)
    elseif kind == "N" then
      local number = tonumber(value)
      if not number or number ~= number or number == math.huge or number == -math.huge then return nil, "Invalid number on line " .. index .. "." end
      target[key] = number
    elseif kind == "B" then
      if value == "1" then target[key] = true elseif value == "0" then target[key] = false else return nil, "Invalid boolean on line " .. index .. "." end
    else return nil, "Unknown value type on line " .. index .. "." end
    count = count + 1
    if count > 10000 then return nil, "Backup contains too many records." end
  end
  local accepted = 0
  for name in pairs(snapshot.stores) do
    if Core.Database:Get(name) then accepted = accepted + 1 end
  end
  if accepted == 0 then return nil, "This backup contains no stores registered by the installed Taverners addons." end
  return snapshot, tostring(accepted) .. " recognised addon stores; " .. tostring(count) .. " records validated."
end

function Core.Backup:RestoreText(source)
  local snapshot, message = self:ParseText(source)
  if not snapshot then return false, message end
  local filtered = {created=snapshot.created, protocol=snapshot.protocol, stores={}}
  for name, saved in pairs(snapshot.stores) do
    if Core.Database:Get(name) then filtered.stores[name] = saved end
  end
  local ok, err = self:RestoreSnapshot(filtered)
  if not ok then return false, err or "Restore failed." end
  return true, message
end

local frame, edit, status
local function Build()
  if frame then return end
  frame = CreateFrame("Frame", "TavernersBackupFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(720, 520); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", 0, -8); frame.title:SetText("Taverners — Backup & Restore")
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", 16, -34); hint:SetText("Export: select all and copy. Import: paste backup text here, validate it, then restore.")
  local scroll = CreateFrame("ScrollFrame", "TavernersBackupScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -58); scroll:SetPoint("BOTTOMRIGHT", -34, 76)
  edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(650); edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  scroll:SetScrollChild(edit)
  status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", 18, 58); status:SetWidth(675); status:SetJustifyH("LEFT")
  local function Button(label, x, callback)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(145, 26); b:SetPoint("BOTTOMLEFT", x, 18); b:SetText(label); b:SetScript("OnClick", callback)
    return b
  end
  Button("Export all addons", 18, function()
    local text, err = Core.Backup:ExportText()
    if text then edit:SetText(text); edit:HighlightText(); status:SetText("Backup generated. Copy the selected text and store it somewhere safe.")
    else status:SetText(err or "Export failed.") end
  end)
  Button("Validate import", 170, function()
    local snapshot, message = Core.Backup:ParseText(edit:GetText())
    status:SetText(snapshot and message or (message or "Validation failed."))
  end)
  Button("Restore backup", 322, function()
    local ok, message = Core.Backup:RestoreText(edit:GetText())
    status:SetText(ok and ("Restore complete. " .. message .. " Reopen module windows to refresh.") or (message or "Restore failed."))
  end)
  Button("Clear", 474, function() edit:SetText(""); status:SetText("") end)
end

function BackupUI:Toggle()
  Build()
  if frame:IsShown() then frame:Hide() else frame:Show(); status:SetText("Backups are local text files; no account or external server is involved.") end
end

SLASH_TAVERNERSBACKUP1 = "/tbackup"
SlashCmdList = SlashCmdList or {}
SlashCmdList.TAVERNERSBACKUP = function() BackupUI:Toggle() end
