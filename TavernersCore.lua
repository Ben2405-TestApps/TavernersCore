-- Taverners Core
-- Shared runtime services for The Taverners Guild addon family.
local ADDON, Core = ...
Core = Core or {}
_G.TavernersCore = Core
Core.name = ADDON or "TavernersCore"
Core.version = "1.0.0"
Core.protocolVersion = 1
Core.modules = Core.modules or {}

Core.Theme = {
  gold = {0.88, 0.68, 0.28},
  parchment = {0.91, 0.84, 0.67},
  muted = {0.72, 0.66, 0.53},
  green = {0.35, 0.78, 0.42},
  red = {0.85, 0.38, 0.30},
  panel = {0.12, 0.085, 0.055, 0.96},
  row = {0.24, 0.18, 0.11, 0.72},
}

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end

Core.Util = {}
function Core.Util:SafeText(value)
  return tostring(value or ""):gsub("|", "/"):gsub("[\r\n]", " "):gsub(";", "/")
end
function Core.Util:Split(value, separator)
  local out = {}
  separator = separator or "|"
  if type(value) ~= "string" then return out end
  local pattern = "(.-)"
  for part in (value .. separator):gmatch(pattern .. separator) do out[#out + 1] = part end
  return out
end
function Core.Util:Now() return (type(time) == "function" and time()) or os.time() end
function Core.Util:SafeCall(fn, ...) return SafeCall(fn, ...) end

Core.Identity = {}
local function PlayerNameRealm()
  local name, realm
  if type(UnitFullName) == "function" then name, realm = UnitFullName("player") end
  name = name or (type(UnitName) == "function" and UnitName("player")) or "Unknown"
  realm = realm or (type(GetRealmName) == "function" and GetRealmName()) or "Unknown"
  return name, realm
end
function Core.Identity:GetPlayer()
  local name, realm = PlayerNameRealm()
  local class
  if type(UnitClass) == "function" then local _, c = UnitClass("player"); class = c end
  return {name=name, realm=realm, class=class, key=name .. "-" .. realm}
end
function Core.Identity:GetKey(name, realm)
  local p = Core.Identity:GetPlayer()
  name, realm = name or p.name, realm or p.realm
  return tostring(name) .. "-" .. tostring(realm)
end
function Core.Identity:ShortName(name)
  if not name then return nil end
  return (tostring(name):match("^([^%-]+)") or tostring(name)):lower()
end
function Core.Identity:SameCharacter(a, b)
  return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

Core.Database = {schemas = {}, stores = {}}
function Core.Database:Register(name, defaults, version)
  assert(type(name) == "string" and name ~= "", "database name required")
  local store = _G[name]
  if type(store) ~= "table" then store = {}; _G[name] = store end
  local schema = self.schemas[name] or {}
  local function Merge(target, source)
    for k, v in pairs(source or {}) do
      if type(v) == "table" then
        if type(target[k]) ~= "table" then target[k] = {} end
        Merge(target[k], v)
      elseif target[k] == nil then target[k] = v end
    end
  end
  Merge(store, defaults or {})
  if version then store.version = math.max(tonumber(store.version) or 0, version) end
  self.schemas[name] = schema
  self.stores[name] = store
  return store
end
function Core.Database:Get(name) return self.stores[name] or _G[name] end
function Core.Database:Wipe(name)
  local store = self:Get(name)
  if type(store) ~= "table" then return false end
  for k in pairs(store) do store[k] = nil end
  return true
end

Core.Profiles = {}
function Core.Profiles:Ensure(db, player)
  if type(db) ~= "table" then return nil end
  player = player or Core.Identity:GetPlayer()
  db.profiles = db.profiles or {}
  local key = player.key or Core.Identity:GetKey(player.name, player.realm)
  local profile = db.profiles[key]
  if type(profile) ~= "table" then
    profile = {key=key, name=player.name, realm=player.realm, class=player.class, professions={}, recipes={}}
    db.profiles[key] = profile
  end
  profile.key, profile.name, profile.realm = key, profile.name or player.name, profile.realm or player.realm
  profile.professions, profile.recipes = profile.professions or {}, profile.recipes or {}
  return profile, key
end
function Core.Profiles:GetMainKey(db, key)
  local links, seen = (db and db.altLinks) or {}, {}
  while links[key] and not seen[key] do seen[key] = true; key = links[key] end
  return key
end
function Core.Profiles:GetAltKeys(db, mainKey)
  local result = {}
  mainKey = self:GetMainKey(db, mainKey)
  for alt, target in pairs((db and db.altLinks) or {}) do
    if self:GetMainKey(db, target) == mainKey then result[#result + 1] = alt end
  end
  table.sort(result)
  return result
end
function Core.Profiles:Link(db, altKey, mainKey)
  if type(db) ~= "table" or not altKey or not mainKey or altKey == mainKey then return false end
  db.altLinks = db.altLinks or {}
  db.altLinks[altKey] = self:GetMainKey(db, mainKey)
  return true
end
function Core.Profiles:Unlink(db, altKey)
  if type(db) ~= "table" or type(db.altLinks) ~= "table" then return false end
  db.altLinks[altKey] = nil
  return true
end

Core.Guild = {online = {}}
function Core.Guild:RefreshRoster()
  self.online = {}
  if not IsInGuild or not IsInGuild() or not GetNumGuildMembers or not GetGuildRosterInfo then return self.online end
  for i = 1, GetNumGuildMembers() do
    local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if name then
      local short = Core.Identity:ShortName(name)
      self.online[short] = online and true or false
      self.online[name:lower()] = online and true or false
    end
  end
  return self.online
end
function Core.Guild:IsOnline(name)
  local short = Core.Identity:ShortName(name)
  return short and self.online and (self.online[short] or self.online[tostring(name):lower()]) or false
end

Core.Config = {}
function Core.Config:Get(db, key, fallback)
  if type(db) ~= "table" then return fallback end
  local value = db[key]
  if value == nil then return fallback end
  return value
end
function Core.Config:Set(db, key, value)
  if type(db) ~= "table" or type(key) ~= "string" then return false end
  db[key] = value
  return true
end

Core.Notifications = {}
function Core.Notifications:Print(message, color)
  local prefix = "|cffd9a441[Taverners]|r "
  local text = tostring(message or "")
  if color and type(color) == "table" then
    local r, g, b = color[1] or 1, color[2] or 1, color[3] or 1
    text = string.format("|cff%02x%02x%02x%s|r", math.floor(r*255), math.floor(g*255), math.floor(b*255), text)
  end
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. text)
  elseif print then print("[Taverners] " .. text) end
end
function Core.Notifications:Toast(message, duration)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(tostring(message or ""), 0.95, 0.78, 0.40, 1, duration or 3)
  else self:Print(message) end
end

Core.Comm = {prefixes = {}, handlers = {}, queue = {}, sending = false, maxBytes = 240}
function Core.Comm:Register(prefix, handler)
  if type(prefix) ~= "string" or prefix == "" then return false end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    local ok = SafeCall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    if ok == false then return false end
  elseif RegisterAddonMessagePrefix then
    SafeCall(RegisterAddonMessagePrefix, prefix)
  end
  self.prefixes[prefix] = true
  if type(handler) == "function" then self.handlers[prefix] = handler end
  return true
end
function Core.Comm:On(prefix, handler)
  if type(handler) ~= "function" then return false end
  self.handlers[prefix] = handler
  return true
end
function Core.Comm:Send(prefix, message, channel, target)
  channel = channel or "GUILD"
  if not self.prefixes[prefix] then self:Register(prefix) end
  if type(message) ~= "string" or #message > self.maxBytes then
    Core.Notifications:Print("A guild message was too long or invalid.")
    return false
  end
  if channel == "GUILD" and (not IsInGuild or not IsInGuild()) then
    Core.Notifications:Print("Join a guild before syncing.")
    return false
  end
  self.queue[#self.queue + 1] = {prefix=prefix, message=message, channel=channel, target=target}
  if not self.sending then
    self.sending = true
    local function Pump()
      local item = table.remove(Core.Comm.queue, 1)
      if not item then Core.Comm.sending = false; return end
      if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        SafeCall(C_ChatInfo.SendAddonMessage, item.prefix, item.message, item.channel, item.target)
      elseif SendAddonMessage then
        SafeCall(SendAddonMessage, item.prefix, item.message, item.channel, item.target)
      end
      if C_Timer and C_Timer.After then C_Timer.After(0.35, Pump) else Core.Comm.sending = false end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, Pump) else Pump() end
  end
  return true
end
function Core.Comm:Dispatch(prefix, message, channel, sender)
  local handler = self.handlers[prefix]
  if handler then SafeCall(handler, message, channel, sender) end
end

Core.Diagnostics = {enabled = false, entries = {}}
function Core.Diagnostics:Log(level, message)
  local entry = {time=Core.Util:Now(), level=tostring(level or "INFO"), message=tostring(message or "")}
  self.entries[#self.entries + 1] = entry
  while #self.entries > 100 do table.remove(self.entries, 1) end
  if self.enabled then Core.Notifications:Print("[" .. entry.level .. "] " .. entry.message) end
end
function Core.Diagnostics:Enable(value) self.enabled = value and true or false end
function Core.Diagnostics:GetReport()
  local p = Core.Identity:GetPlayer()
  return {
    addon=Core.name, version=Core.version, protocol=Core.protocolVersion,
    player=p, inGuild=(IsInGuild and IsInGuild()) or false,
    registeredPrefixes=(function() local n=0; for _ in pairs(Core.Comm.prefixes) do n=n+1 end; return n end)(),
    recentEntries=self.entries,
  }
end

function Core:RegisterModule(name, module)
  if type(name) ~= "string" or type(module) ~= "table" then return false end
  self.modules[name] = module
  return true
end

local frame = CreateFrame("Frame")
Core.EventFrame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local loaded = ...
    if loaded == ADDON then
      Core.loaded = true
      Core.Notifications:Print("Core " .. Core.version .. " ready.")
    end
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, channel, sender = ...
    if Core.prefixes[prefix] then Core.Comm:Dispatch(prefix, message, channel, sender) end
  end
end)
