# CombatTracking
World of Warcraft addon (3.3.5a)
Tracks combat status of your target, focus, party members and arena enemies (arena1, arena2, etc)
![изображение](https://user-images.githubusercontent.com/17499770/155911361-cfecfa32-78d8-42d6-8e0d-47ecca6e4cd4.png)
![изображение](https://user-images.githubusercontent.com/17499770/155911408-d6497328-c804-4ab9-99fd-37403359a289.png)

## How it works
- Each tracked unit gets an icon. By default it is bright while the unit is **out of combat** (for example: it can
  be sapped) and dimmed in combat. The "Inverted" option swaps this.
- While a unit is in combat, a swipe shows when it can leave combat. The addon follows the server's rules:
  - PvP combat is kept per pair of units and ends 5 seconds after the last hostile contact of the pair (melee,
    hostile spells that hit or miss, hostile casts). Periodic damage and healing do not refresh it.
  - When an opponent dies, its contacts no longer count. Vanish and Feign Death drop only the unit's own combat
    (a hunter in Feign Death shows as out of combat, not as dead).
  - Attacking a pet also puts its owner in combat with the attacker.
  - Healing or buffing a unit in combat puts the helper in combat with that unit's opponents.
  - Spells without initial aggro (Sap, Hunter's Mark, Blessing of Wisdom, ...) only count on a target already in
    combat. The spell list is generated from the game data (`tools/gen_spelldata.py`).
  - Mass Dispel on a unit without buffs refreshes combat, but the game logs nothing for that hit and gives no
    positions. When the caster or one of its enemies is still in combat after its timer ran out, a Mass Dispel
    finished since its last known contact explains it: the timer continues from the Mass Dispel. In arena every
    caster has a unit token, so the Mass Dispel's time is exact.
  - Fighting NPCs has no timer: the swipe stays full.
  - The exact duration is measured on each realm from observed combats, mostly your own (options: General >
    Combat timer), and can be set by hand.
  - With "Show timer", the icon counts down the seconds; "?" means the unit is still in combat past its timer (a
    contact out of combat log range) or your client does not see it (a stealthed arena enemy, a far party
    member). A unit that is not seen keeps its last state.
- A sound plays when a unit leaves combat. Units that die or change (a new target, another party member) never play a
  sound.
- Arena icons can be attached to Gladius.

## Commands
- `/ct` - options (General, Sounds, Units, Profiles)
- `/ct lock` - unlock / lock the icons. Unlocked icons can be dragged; right click disables an icon, Ctrl + right
  click turns its sound off.
- `/ct test` - test mode: shows every enabled icon with sample combat states
- `/ct reset` - reset the current profile

## Options
- Per unit: enabled, sound, anchor frame (any frame name, for example the frame of your unit frames addon; the icon
  moves with it), reset position.
- Sounds for entering combat, leaving combat and your own leaving combat (any LibSharedMedia sound).
- Icon, scale, dimmed opacity (0 hides dimmed icons), unit names, countdown timer, only players (on by default:
  the addon is meant for PvP), hide party icons in raids, attach to Gladius.
- Profiles (AceDB). Settings from versions before 3.0 are migrated automatically.

## Limitations
- Only unit tokens are tracked (player, target, focus, party1-4, arena1-5). In battlegrounds there are no arena
  tokens, so only target and focus work there.
- Which units a Mass Dispel hit is not known, so the timer of a unit it hit only switches to the Mass Dispel once
  its old timer has run out (0.3 s later). A Mass Dispel from a caster without a unit token (outside arena) is
  not seen.
