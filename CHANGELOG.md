# Changelog

## [0.3.0-beta] - 2026-10-16

### New Features

- Blizzard Draws This Icon: on an Icon aura with one Aura trigger on Player, Target or Focus (not debuffs on you), Blizzard draws the icon, swipe and timer, in combat too, the moment the aura changes. The aura's own texts, borders and glows hide while Everything Auras is unsure
- Its On Show and On Hide sound files play through Blizzard, so they play in combat too. Blizzard stops a sound after 5 seconds, and with Own Only set the aura keeps its own sounds
- On Target or Focus, Blizzard draws buffs only on friendly units and debuffs only on enemies. Otherwise Everything Auras draws the icon as usual
- ForeverAuras' Aura (Modern) icons that Blizzard can draw have it switched on, also the ones you imported before, and their note says so

### Improvements

- Item triggers list the Ammo and Ranged slots, and no longer list profession slots WoW Forever doesn't have
- What's New and the In Combat page describe icons Blizzard draws

### Bug Fixes

- The cast tracking behind estimated buffs no longer keeps casts that ended out of combat or failed
- An unused file is no longer included in the download

## [0.2.0-beta] - 2026-10-13

The first public beta of Everything Auras, a modified fork of WeakAuras for WoW Forever, built on M33kAuras.

### New Features

- WeakAuras on WoW Forever, with its own saved auras, settings and commands (/eauras, plus /wa and /ea when no other addon uses them)
- Imports from WeakAuras, M33kAuras and ForeverAuras. ForeverAuras' "Aura (Modern)" triggers become standard Aura triggers matched by spell name, its spec restrictions become class restrictions, and its media paths point at the same files
- In combat, an aura Forever hides stays shown as last known, dimmed with a corner marker, and your own buffs start over from your casts. Nothing unsure plays a sound, glows or sends chat
- Warnings on auras that use the combat log, secret health values or functions Forever lacks, and stand-ins for older Classic functions inside custom code
- An aura whose custom code causes 10 Lua errors in a session has that code switched off, with a button to turn it back on
- The Everything Auras window (In Combat, General and About), What's New, an options window in the same look as my other addons, and its own logo
