if not EverythingAuras.IsLibsOK() then return end
---@class Private
local Private = select(2, ...)

-- Only the retail TOC lists this file, so Forever never runs it and keeps its own wording.
if not EverythingAuras.IsRetail() then return end

local L = EverythingAuras.L

-- Each key is the Forever text as the EA files write it. tests/ea_retail_test.lua fails on a key they no longer use.
for key, value in pairs({
  ["In combat, WoW Forever hides the details of auras from addons. Everything Auras can tell that an aura was added or removed, but not which one."]
    = "In combat, WoW hides the details of most auras from addons. The ones it never hides stay exact, and Browse never-secret auras on the Trigger tab lists them.",
  ["When you cast one of your own buffs on yourself, it starts over from your cast as an %s, with the length Everything Auras learned out of combat. A buff of the same length that it replaces, such as another seal, goes away."]
    = "When you cast one of your own buffs on yourself, it starts over from your cast as an %s, with the length Everything Auras learned out of combat. A buff of the same length that it replaces goes away.",
  ["A dimmed aura never plays a sound, glows, sends chat or runs its actions. A Missing reminder waits for the fight to end instead of appearing from a guess. When the fight ends, everything is read again."]
    = "A dimmed aura never plays a sound, glows, sends chat or runs its actions. A Missing reminder waits instead of appearing from a guess. Once auras can be read again, everything is read again.",
  ["In combat: holds what it showed when the fight started, until the fight ends."]
    = "In combat: holds what it showed when the fight started, until auras can be read again.",
  ["In combat Everything Auras keeps what it read before the fight, so a Missing reminder holds until the fight ends instead of appearing from a guess."]
    = "In combat Everything Auras keeps what it read before the fight, so a Missing reminder holds until auras can be read again instead of appearing from a guess.",
  ["The aura's own texts, borders and glows hide while Everything Auras is unsure in combat. Its On Show and On Hide sound files play through Blizzard, so they play in combat too. Blizzard stops a sound after 5 seconds, and with Own Only set the aura keeps its own sounds. ForeverAuras' Aura (Modern) icons that Blizzard can draw have it switched on, also the ones you imported before."]
    = "The aura's own texts, borders and glows hide while Everything Auras is unsure in combat. Its On Show and On Hide sound files play through Blizzard, so they play in combat too. Blizzard stops a sound after 5 seconds, and with Own Only set the aura keeps its own sounds.",
  ["Closed to addons on WoW Forever. Auras that need it stay off and carry a warning."]
    = "Closed to addons. Auras that need it stay off and carry a warning.",
  ["Strings from WeakAuras, M33kAuras and ForeverAuras import. ForeverAuras' Aura (Modern) triggers become standard Aura triggers matched by spell name, its spec restrictions become class restrictions, and its media paths point at the same files here. Each converted aura carries a note."]
    = "Strings from WeakAuras and M33kAuras import.",
  ["An aura that uses something WoW Forever lacks, such as the combat log, secret health values or an old function with no stand-in, carries a warning icon that says what won't work."]
    = "An aura that uses something addons can no longer do, such as the combat log, math on secret health values or an old function with no stand-in, carries a warning icon that says what won't work.",
  ["Older Classic functions that WoW Forever lacks, such as GetSpellInfo and UnitBuff, have stand-ins inside aura custom code. UnitBuff and the other aura reads work out of combat and return nothing while auras are hidden."]
    = "Older functions that WoW no longer has, such as GetSpellInfo and UnitBuff, have stand-ins inside aura custom code. UnitBuff and the other aura reads work out of combat and return nothing while auras are hidden.",
  ["A modified fork of WeakAuras for WoW Forever, built on M33kAuras. Maintained by Wheelbarrel00."]
    = "A modified fork of WeakAuras, built on M33kAuras. Maintained by Wheelbarrel00.",
  ["Uses the combat log, which WoW Forever closes to addons. That part never fires."]
    = "Uses the combat log, which WoW closes to addons. That part never fires.",
  ["Uses a trigger Everything Auras does not have on WoW Forever, so that trigger stays off: %s"]
    = "Uses a trigger Everything Auras does not have, so that trigger stays off: %s",
  ["Custom code calls functions WoW Forever does not have, so that code will cause errors: %s"]
    = "Custom code calls functions WoW does not have, so that code will cause errors: %s",
  ["Custom code reads UnitHealth. Health is a secret value on WoW Forever, so math or comparisons on it cause errors."]
    = "Custom code reads UnitHealth. Health is a secret value, so math or comparisons on it cause errors.",
  ["Custom code reads auras with UnitAura, UnitBuff or UnitDebuff. On WoW Forever these return nothing while Blizzard keeps auras secret, for example in combat."]
    = "Custom code reads auras with UnitAura, UnitBuff or UnitDebuff. These return nothing while Blizzard keeps auras secret, for example in combat.",
  ["In combat WoW Forever hides most auras from addons, so Everything Auras shows what it last knew. Dim fades it and adds a small corner marker. Sounds, glows, chat and custom actions never fire for it, whatever you pick."]
    = "In combat WoW hides most auras from addons, so Everything Auras shows what it last knew. Dim fades it and adds a small corner marker. Sounds, glows, chat and custom actions never fire for it, whatever you pick.",
  ["This mode reads the combat log, which WoW Forever closes to addons."]
    = "This mode reads the combat log, which WoW closes to addons.",
}) do
  L[key] = value
end

-- Forever's example spells do not exist here: a never-secret buff, then a secret aura, then a buff you recast.
Private.EARetailExampleSpells = { 21562, 465, 190784 }
