<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/patch-notes.jpg" alt="Patch notes" width="100%">
</p>

# Patch notes

## 1.0.0.4

- Fix: a silo extension attached to a silo that has only an unloading point (or only a loading point) is counted into that silo instead of showing as a separate silo.
- Fix: feeding robot: a bin holding a feed type the game no longer knows (for example from a removed mod) is left out, and the other bins no longer show the wrong amounts.
- Fix: Show Stations no longer lists goods of which only a residue under half a litre is left, same as the inventory list.
- If a game update changes the Prices menu, the mod switches its Inventory tab off with a log line instead of causing a script error while loading.
- Offline tests (`tests/test_offline.py`, 31 tests), run by every build.

## 1.0.0.3

- Description in all 27 game languages (GIANTS ModHub layout).
- The title is **Farm Inventory Plus** again (was Farm Inventory Pro Edition).
- ModHub screenshots at 1600x900 without captions.

## 1.0.0.2

- Description in GIANTS' ModHub layout (category, price, upkeep or hotkeys at the top).

## 1.0.0.1

- Updated for the current game version: modDesc descVersion 116 (the game build of 2026-10-27; GIANTS TestRunner 0.9.24 accepts only 116).

## 1.0.0.0
- Meets the GIANTS ModHub checks (TestRunner): textures, icon and modDesc brought up to date.
- Errors are no longer hidden: they show in the log.

## 0.7.2.1

- The author now shows as **DTM Mods, PropaineX** in the mod list.

## 0.7.2.0
- Closing the menu from the INVENTORY tab no longer lags, Esc only needs one press, and the mouse wheel scrolls the list again.
- The HIDE / SHOW HIDDEN buttons now show up on the INVENTORY tab.

## 0.7.1.0
- Fixed an error that filled the log with thousands of lines while the menu was open.

## 0.7.0.0
- HIDE / UNHIDE a whole storage location in the INVENTORY tab, and a SHOW HIDDEN toggle to bring them back. Your hidden list is saved per player.

## 0.6.0.0
- Feeding robots get their own section after the silos, with every bin shown as stored / capacity (also works with the Pig Barn With Robot hoppers).
- Liquid storage (milk, water, diesel and so on) is listed right after the dry silos.

## 0.5.0.0
- Renamed from My Silo Prices Tab to Farm Inventory; the tab is now called INVENTORY.
- Stock is listed per storage location: silos (with their silo extensions), bunker silos, productions and animal pens.
- Productions only list what they make, not their inputs.
- Remove the old My Silo Prices Tab mod, or both tabs will show.
