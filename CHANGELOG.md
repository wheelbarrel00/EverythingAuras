# Changelog

## [0.6.0-beta] - 2026-11-13

Everything in this version is for WoW Forever. Nothing changes on Retail.

### New Features

- Bag Space trigger: free, used and total slots and free space, for all bags or general bags (specialty bags not yet tested in game)
- Equipment Durability trigger: overall and lowest durability, broken items, and the most worn item's name
- Ammo trigger: the ammo in your bags, all of it or by item ID (ammo in the ammo slot not yet tested in game)
- Range Check, Spell in Range and Spell in Range (Action Bar) triggers, in and out of combat
- Tracking trigger for your tracking spells and map filters, with Any Tracking Spell for when none of your tracking spells is on
- Role trigger for your assigned group role (not yet tested in game with a role assigned)
- Specialization load option: an aura loads for the talent tree with 21 or more points and the most points, the tree further left on a tie. Click a tree once to load for it, twice to never load for it (tested in game below 21 points only)
- Load Flag load option, set and read from custom code with SetLoadFlag, SetLoadFlags and LoadFlag
- Money triggers can check gold, silver and copper
- Stance/Form/Aura can check a form by its form ID (shapeshift forms and stances not yet tested in game)
- Weapon Enchant has an Enchant Type: Any, Imbue, or Oil, Stone or Poison (imbues not yet tested in game)

### Improvements

- Imported auras with a talent spec setting now load by talent tree, as above, instead of loading for every tree. Until a tree has 21 or more points, an aura set to load for a spec stays unloaded
- Imported Cooldown Manager triggers become standard triggers. The aura's note names any extra spells, and its warning names settings that did not carry over
- Imported Modern Aura Groups are laid out as a fixed row
- Imported custom code that calls AuraOverlay, WatchSwingTimer or GetSwingTimerInfo now works, and the options send their open and close events to custom code
- After you import a ForeverAuras string, a summary lists what was converted and which auras still have a warning
- /fa opens Everything Auras when no other addon uses it at login

## [0.5.1-beta] - 2026-11-10

### Improvements

- An ignore list of exact spell IDs no longer stops Blizzard from drawing the icon
- Imported auras now name what Everything Auras cannot do yet, such as functions their custom code calls or a Load Flag, and Health filters it has to ignore because health is secret, instead of dropping them silently

### Bug Fixes

- Imported ForeverAuras Aura (Modern) triggers with Total Time set to "=" now keep that filter
- Imported Aura (Modern) triggers keep Own Only
- Spell names typed into an imported Aura (Modern) trigger are kept, and its ignored spell IDs carry over
- Auras you imported before this update get these fixes at your next login
- Imported swing timers keep their off hand or ranged setting (ranged not yet tested in game)
- Updated the bundled LibRangeCheck-3.0 to its newest version, which adds a fix for WoW Forever

## [0.5.0-beta] - 2026-11-07

### New Features

- Spell cooldown auras keep a time left in combat, learned the last time you used the spell out of combat. Conditions, the trigger's Remaining Time and sorting by time left work mid-fight, and the estimate never plays sounds, sends chat, runs custom code or shows glows
- Blizzard Draws This Bar on Progress Bars: Blizzard draws the bar, its icon, its name and its time in combat too
- A text that shows only %s becomes Blizzard's stack count on auras Blizzard draws
- Blizzard can draw buffs on your pet and on a party or raid member set as a Specific Unit (not yet tested in game)

### Improvements

- Blizzard Draws This Icon and Blizzard Draws This Bar are on by default, also for auras you already have, unless you turned them off. An existing aura starts once Everything Auras knows its spell IDs, from the options or from seeing the buff out of combat
- A spell ID typed in Name(s) gives Blizzard every rank of that spell on WoW Forever too

## [0.4.0-beta] - 2026-11-01

### New Features

- Everything Auras now runs on Retail as well as WoW Forever
- On Retail, auras Blizzard never hides stay exact in combat, and Browse never-secret auras on the Trigger tab lists them
- Retail has its own What's New and its own wording on the In Combat page

### Improvements

- Premade Auras and Apply Template stay off on Retail, because their data predates Midnight
- Removed three optional dependencies that nothing in Everything Auras uses

## [0.3.3-beta] - 2026-10-18

### Bug Fixes

- Auras with Show On set to Always no longer stay dimmed after combat when the buff ran out during the fight
- A change to your group during combat no longer clears the buffs your Player auras show
- A seal swapped at the very start of a fight replaces the old one right away
- Hovering the icon of a buff you recast in combat shows that spell's tooltip
- The Global Cooldown trigger no longer stays on screen for a whole fight
- Custom triggers whose Duration Info returns secret values, such as UnitHealth, no longer cause Lua errors
- When Everything Auras switches off an aura's custom code after repeated errors, its custom animations stop erroring too, and a new aura with a deleted aura's name no longer starts with its custom code off
- Blizzard Draws This Icon keeps all of its spell ranks while the options rebuild their spell list after an update

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
