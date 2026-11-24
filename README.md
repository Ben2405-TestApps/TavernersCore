# Taverners Core

**Version:** 1.0.0  
**Interface target:** 16001 (verify against the current WoW Forever client)

Taverners Core is the shared runtime library for addons maintained by The Taverners Guild. It centralises common services so each addon does not need to maintain its own copy.

## Installation

1. Install the folder as `Interface/AddOns/TavernersCore`.
2. Install any Taverners addon that declares TavernersCore as a required dependency.
3. Ensure TavernersCore is enabled in the AddOns list. WoW loads required dependencies first.

## Public API

The library is exposed as `_G.TavernersCore`.

- `TavernersCore.version`, `protocolVersion`, `loaded`
- `TavernersCore.Theme`: shared gold, parchment, muted, green, red and panel colours.
- `TavernersCore.Identity:GetPlayer()`: current name, realm, class and stable character key.
- `TavernersCore.Identity:GetKey(name, realm)`, `ShortName(name)`, `SameCharacter(a,b)`.\n- `TavernersCore.Profiles:Ensure(db, player)`, `GetMainKey(db,key)`, `GetAltKeys(db,key)`, `Link(db,alt,main)`, `Unlink(db,alt)`.\n- `TavernersCore.Guild:RefreshRoster()` and `IsOnline(characterName)` for guild roster presence.
- `TavernersCore.Database:Register(savedVariableName, defaults, version)`, `Get(name)`, `Wipe(name)`.
- `TavernersCore.Comm:Register(prefix, handler)`, `On(prefix, handler)`, `Send(prefix, message, channel, target)`.
- `TavernersCore.Notifications:Print(message)`, `Toast(message)`.
- `TavernersCore.Config:Get(db,key,fallback)`, `Set(db,key,value)`.
- `TavernersCore.Diagnostics:Log(level,message)`, `Enable(bool)`, `GetReport()`.
- `TavernersCore.Util:SafeText(value)`, `Split(value, separator)`, `Now()`, `SafeCall(fn,...)`.

## Communication

Addon messages are queued and rate-spaced by the Core communication service. Register a prefix with a handler, then send messages through the same service. The service enforces the conservative 240-byte message limit used by the initial Taverners addons. Guild messages require the player to be in a guild. The Core dispatches messages only to the handler registered for that prefix.

## Compatibility and safety

- Written in Lua using the standard WoW addon environment; no external libraries or network access.
- Saved-variable stores are registered by name and remain owned by the consuming addon.
- Core does not attempt to identify accounts securely: character keys are name/realm identifiers.
- Addon-message communication is peer-to-peer with online guild members running compatible addons, not a central server.
- Interface number and API availability must be validated in the live WoW Forever client.
- Diagnostics are local and bounded to the latest 100 entries. They do not transmit player data.

## Development

Keep shared behaviour in Core and addon-specific data/business logic in the consuming addon. Increment the protocol version only when changing shared wire-level conventions.
