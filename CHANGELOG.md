# Changelog

## [0.2.0-beta] - 2026-10-13

The first public beta of Everything Auras, a modified fork of WeakAuras for WoW Forever, built on M33kAuras.

### New Features

- WeakAuras on WoW Forever, with its own saved auras, settings and commands (/eauras, plus /wa and /ea when no other addon uses them)
- Imports from WeakAuras, M33kAuras and ForeverAuras. ForeverAuras' "Aura (Modern)" triggers become standard Aura triggers matched by spell name, its spec restrictions become class restrictions, and its media paths point at the same files
- In combat, an aura Forever hides stays shown as last known, dimmed with a corner marker, and your own buffs start over from your casts. Nothing unsure plays a sound, glows or sends chat
- Warnings on auras that use the combat log, secret health values or functions Forever lacks, and stand-ins for older Classic functions inside custom code
- An aura whose custom code causes 10 Lua errors in a session has that code switched off, with a button to turn it back on
- The Everything Auras window (In Combat, General and About), What's New, an options window in the same look as my other addons, and its own logo
