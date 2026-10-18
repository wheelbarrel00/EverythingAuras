# Changelog

## [0.3.2-beta] - 2026-10-18

### New Features

- Character Stats triggers can check your Holy, Fire, Nature, Frost, Shadow and Arcane resistances, the same values your character window shows
- Unit Characteristics triggers can check a unit's creature family

### Improvements

- The options keep their spell list between sessions instead of rebuilding it the first time you open them in each session
- The Browse never-secret buttons are gone, since WoW Forever has no never-secret auras, cooldowns or casts
- Power Type lists only Mana, Rage, Focus, Energy and Combo Points
- The texture picker lists the Everything Auras logo
- Updated to M33kAuras 5.20.7-rg4-m101

### Bug Fixes

- With Use Display Info Id on, Model auras no longer offer the unit model and the model picker, which do not apply to display IDs
- Two Blizzard spark textures that WoW Forever does not have are no longer listed

## [0.3.1-beta] - 2026-10-17

### Bug Fixes

- The 0.3.0-beta download had a broken copy of one bundled library (Archivist), which caused a Lua error at login. Bundled libraries are now packaged exactly as they are

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
