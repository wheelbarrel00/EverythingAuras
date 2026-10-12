# Notice

Everything Auras is a modified fork of WeakAuras for WoW Forever, built on M33kAuras.

- **WeakAuras**, by the WeakAuras Team and its contributors: https://github.com/WeakAuras/WeakAuras2
- **M33kAuras**, m33shoq's port of WeakAuras to the Midnight engine, by m33shoq and its contributors:
  https://github.com/m33shoq/M33kAuras

Everything Auras is not an official release of, or endorsed by, either project. It is maintained by
Wheelbarrel00.

## License

Everything Auras is distributed under the GNU General Public License, version 2 (see `LICENSE`, also shipped in
every addon folder). It comes with no warranty. The copyright notices of WeakAuras and M33kAuras remain in effect.

Bundled libraries, fonts, sounds and textures keep their own licenses. See each library's folder and file
headers.

## Changes

Every file Everything Auras changed carries a notice line saying so. The git history of this repository records
each change and its date.

- 2026-10-11: Based on M33kAuras 5.20.7-rg4-m99. Renamed folders, files, identifiers, saved variables, slash
  commands and addon-message prefixes from M33kAuras to Everything Auras with `tools/ea_transform.py`. Limited
  the TOC files to WoW Forever.
- 2026-10-11: Removed the login code that enabled and disabled any addon named WeakAuras, the settings-wipe
  helper and the hooks for a guild's private addons. Closed custom-code access to the addon's internal tables.
  Fixed custom text receiving empty values for duration-based progress. Claimed `/wa` and `/ea` only when no
  other addon uses them. Took 15 fixes from WeakAuras (listed in `tools/wa-picks.tsv`).
- 2026-10-11: Fixed errors on WoW Forever in the loss-of-control cooldown and in power bars on other units.
  Restored aura tooltip values out of combat. Replaced every deprecated Blizzard function so nothing depends on the
  `loadDeprecationFallbacks` setting. Turned on creature type, summon pending and the SAY and YELL note for
  Forever. Hid the trigger templates on Forever, whose template data is retail-only.
- 2026-10-11: Added imports of ForeverAuras exports: their aura data is read as the WeakAuras version it really
  is, "Aura (Modern)" triggers become standard Aura triggers matched by spell name, ForeverAuras media paths
  point at the same files in Everything Auras, and custom code that names `ForeverAuras` or its swing timer
  event keeps working. Added Everything Auras' own migration counter.
- 2026-10-11: Added stand-ins for older Classic functions that WoW Forever lacks, available only to aura custom
  code. Added warnings on auras that use the combat log, secret health values, missing functions or trigger events
  Everything Auras does not have. A trigger with an unknown event now keeps its name and stays off instead of
  turning into an always-on Conditions trigger.
- 2026-10-11: Imported ForeverAuras auras restricted to a WoW Forever spec now load by the matching Player Class.
  Added a warning on auras that use ForeverAuras' talent spec load option.
- 2026-10-11: The Aura trigger no longer drops every tracked aura on a unit when an aura changes in combat. An
  aura WoW Forever hides from addons stays shown as last known, dimmed with a marker, until its timer runs out,
  and never fires sounds, glows, chat or custom actions. Missing reminders wait until combat ends. Added a
  per-aura "When Unsure in Combat" option.
- 2026-10-11: In combat, casting one of your own buffs on yourself restarts it as an estimate with the length
  learned out of combat, and a buff of the same length that it replaces (such as another seal) is dropped.
