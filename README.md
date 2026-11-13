# Everything Auras

Everything Auras brings WeakAuras to Retail and WoW Forever. It is a modified fork of WeakAuras, built on M33kAuras,
and it keeps WeakAuras' behavior as close to the original as the game allows.

**Status:** beta, on Retail and WoW Forever. The first public version is 0.2.0-beta.

## Why Everything Auras

In combat, WoW hides most aura details from addons. That is the hard part of running WeakAuras on Retail and WoW
Forever, and it is what Everything Auras is built to handle.

- **Blizzard draws your auras:** on by default, Blizzard itself draws many of your Icon and Progress Bar auras
  mid-fight, with their timers and stack counts, and plays their On Show and On Hide sounds.
- **Cooldowns keep count:** each spell's cooldown length is learned out of combat, so cooldown auras change color and
  sort by time left mid-fight.
- **Honest in combat:** an aura the game hides stays on screen as last known, dimmed with a small corner marker, and
  nothing unsure ever plays a sound, glows or sends chat.
- **Your own buffs keep up:** cast one of your own buffs on yourself mid-fight and it starts over from your cast.
- **Clear warnings:** auras that need something the game no longer allows are marked before the pull, and one broken
  aura can't flood your errors.
- **Imports that say what happened:** strings from WeakAuras and M33kAuras import as they are, and on WoW Forever,
  ForeverAuras strings convert as they import, with a note on each converted aura and a summary of what was converted.
- **Safe to try:** it keeps its own saved auras and never touches another aura addon's data.

## Credit

Everything Auras exists because of the work of others:

- **WeakAuras**, by the WeakAuras Team and its contributors: https://github.com/WeakAuras/WeakAuras2
- **M33kAuras**, m33shoq's port of WeakAuras to the Midnight engine: https://github.com/m33shoq/M33kAuras

Everything Auras is not an official release of, or endorsed by, either project.

## License

GPL-2.0. See `LICENSE` and `NOTICE.md`.
