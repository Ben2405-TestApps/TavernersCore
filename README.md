# Taverners Core

**Version:** 1.3.0  
**Interface target:** 16001 (verify against the current WoW Forever client)

Taverners Core is the shared runtime library for addons maintained by The Taverners Guild. It centralises common services so each addon does not need to maintain its own copy.

## Installation

1. Install the folder as `Interface/AddOns/TavernersCore`.
2. Install any Taverners addon that declares TavernersCore as a required dependency.
3. Ensure TavernersCore is enabled in the AddOns list. WoW loads required dependencies first.

## In-game diagnostics

Type `/tcore` or `/tavdiagnostics` to open the diagnostics window.

The window includes:
- Core version, protocol version, game build and current character details.
- A dependency scan that finds addons declaring TavernersCore as a dependency, reports whether they loaded, and lists any missing dependencies they require.
- Registered communication prefixes and queued messages.
- Registered Taverners modules.
- The latest 12 local diagnostic log entries.
- Refresh and verbose-logging controls.

The dependency scan checks addon metadata exposed by the game client. Addons marked load-on-demand may correctly appear as not loaded until requested. The report stays on the local client and is not transmitted.

## Public API

The library is exposed as `_G.TavernersCore`.

- `TavernersCore.version`, `protocolVersion`, `loaded`
- `TavernersCore.Theme`: shared gold, parchment, muted, green, red and panel colours.
- `TavernersCore.Identity:GetPlayer()`: current name, realm, class and stable character key.
- `TavernersCore.Identity:GetKey(name, realm)`, `ShortName(name)`, `SameCharacter(a,b)`.
- `TavernersCore.Profiles:Ensure(db, player)`, `GetMainKey(db,key)`, `GetAltKeys(db,key)`, `Link(db,alt,main)`, `Unlink(db,alt)`.
- `TavernersCore.Guild:RefreshRoster()` and `IsOnline(characterName)` for guild roster presence.
- `TavernersCore.Database:Register(savedVariableName, defaults, version)`, `Get(name)`, `Wipe(name)`.
- `TavernersCore.Comm:Register(prefix, handler)`, `On(prefix, handler)`, `Send(prefix, message, channel, target)`.
- `TavernersCore.Notifications:Print(message)`, `Toast(message)`.
- `TavernersCore.Config:Get(db,key,fallback)`, `Set(db,key,value)`.
- `TavernersCore.Diagnostics:Log(level,message)`, `Enable(bool)`, `GetReport()`, `CheckDependencies()`, `BuildText()`, `Show()`.
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


## Suite expansion (1.2.0)

- Added a shared settings registry and `/tsettings` window for registered module preferences.
- Added an internal event bus for addon-to-addon refresh and state notifications.
- Added table-based snapshot/restore primitives for registered SavedVariables stores. At 1.2.0 these were developer-facing APIs; 1.3.0 adds the user-facing portable backup/import workflow.
- Added module status reporting for Guild Hall and diagnostics integrations.

Settings currently appear when installed addons register them. The window currently edits boolean and numeric preferences.


## Portable backup and restore (1.3.0)

- Added `/tbackup`, a user-facing backup and restore window.
- Export creates a portable plain-text snapshot of all SavedVariables stores registered by currently loaded Taverners addons.
- Import validates the format, record count, nesting and value types before changing any registered store.
- Import treats the backup as data; it does not execute Lua, use `loadstring`, or accept arbitrary code.
- Only stores registered by installed Taverners addons are restored; unrelated stores in an imported file are ignored.
- Backups are manual local text exports. No cloud service or automatic remote storage is used.

After restoring, reopen module windows or use their refresh commands to update displayed information.
