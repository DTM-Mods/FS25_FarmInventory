# FS25_FarmInventory (Farm Inventory Pro Edition)

Farming Simulator 25 mod by PropaineX. Adds an **INVENTORY** tab next to PRICES in the in-game
Prices menu that lists only goods stored in the player's own silos, with the normal market info
(stations, prices, price history). Status: v0.1.0.0 tab tested in singleplayer (Oct 2026); v0.2.0.0 adds the silo load filter (untested); v0.3.0.0 also counts own production points (untested); v0.4.0.0 puts production goods in a PRODUCTIONS
section and writes the stored amount into every row (untested).
Renamed from SiloPricesTab to MySiloPricesTab on 2026-10-19, then to FarmInventory on 2026-10-29 (v0.5.0.0, names only on top of the 0.4.3.0 code: folder, files, Lua global `FarmInventory`, title "Farm Inventory Pro Edition", tab label "INVENTORY", zip `FS25_FarmInventory.zip`). Plans for the per-location list: see HANDOFF_2026-10-29.md.

## Files
- `modDesc.xml` - mod descriptor (descVersion 111). Icon is `icon_farmInventory.dds`.
- `scripts/FarmInventory.lua` - the INVENTORY prices tab.
- `scripts/SiloLoadFilter.lua` - (v0.2.0.0) the R fill-type list at a silo/load trigger only shows goods in stock
  (>= 0.5 L). Wraps `LoadTrigger.toggleLoading` and swaps `source.getAllFillLevels` for a filtered version while it
  runs. Skipped for infinite-capacity triggers; if nothing is in stock the game's own list is used. Checked against
  `debugger\gameSource.zip` dataS/scripts/triggers/LoadTrigger.lua:432 (dialog shows for 1+ types unless autoStart).
  Dispatches via `LoadTrigger.sltHandler`.
- `translations/l10n_en.xml` - `ui_sptTabLabel` ("INVENTORY"), `ui_sptNoGoods`.
- `icon_farmInventory.png` - editable icon source (512x512, not shipped). `.dds` is the shipped version.
- `scripts/SiloPricesDiag.lua` - old diagnostic that dumps `InGameMenuStatisticsFrame` to log.txt
  with `[SPT-DIAG]` prefix. Not shipped; re-enable in modDesc if the menu changes in a game update.
- `tools/build.ps1` - builds `FS25_FarmInventory.zip` into `Testing_local` (`-ConvertIcon` regenerates the .dds
  with GIANTS textureTool, BC7 + mips).
- `tools/make_icons.ps1 -OutDir <dir>` - System.Drawing script that drew the icon options (B was chosen).

## Build / test loop
1. Game must be fully closed (it locks the zip).
2. `powershell -ExecutionPolicy Bypass -File tools\build.ps1`
3. User enables the mod for the savegame, tests, quits.
4. Read `Documents\My Games\FarmingSimulator2025\log.txt` for errors (ignore the many
   `g_configurationManager` / `registerColorConfigurationXMLPaths` errors from other mods).

## How it works
- The prices page lives in `InGameMenuStatisticsFrame` (`g_inGameMenu.pageStatistics`),
  sub-tab `SUB_CATEGORY.PRICES = 1`. Product list data is `frame.fillTypes` = one array per
  section (1 = crops, 2 = other); entries are fill type objects (`.index`).
- No new paging state is added because FS25_SortableVehicleTabbing (installed) uses index 6+. Instead
  the MY SILOS button is a clone of the PRICES tab button. Clicking it sets `frame.sptActive`, runs
  the game's own PRICES click handler, and then swaps `frame.fillTypes` for a filtered copy.
  Clicking PRICES, changing tab, or closing the menu restores the full list.
- (v0.5.0.0) Own stock = `FarmInventory.getOwnLocations(farmId)`: one location per placeable owned by the farm, in
  order silos (`spec_silo.storages`), bunker silos (`spec_bunkerSilo.bunkerSilo.fillLevel`; fill type = inputFillType,
  or outputFillType when state is CLOSED/FERMENTED/DRAIN, as in BunkerSilo:update), productions
  (`spec_productionPoint.productionPoint.storage`, ONLY the goods in `outputFillTypeIds`: the user doesn't want inputs,
  they can't be taken back out; if that field is nil every good shows. Field name unverified: ProductionPoint:load is
  stripped), animal pens (`spec_husbandry.storage`).
- (v0.6.0.0) FEEDING ROBOT sections come right after the silos (dry, then liquid): one per owned placeable with
  `spec_husbandryFeedingRobot`, listing EVERY bin, empty ones too, as "stored / capacity" with the price texts blanked.
  Bins = `feedingRobot.unloadingSpots[i]` (.fillLevel, .capacity; fill type field unverified, FeedingRobot.lua is not in
  gameSource.zip: tries .fillTypes, .fillTypeIndex/.fillType, robot.fillTypeToUnloadingSpot; logs the spot's fields once
  with [FarmInventory] if none). FS25_PigBarnWithRobot (Fennell) keeps its hoppers in
  `placeable["spec_FS25_PigBarnWithRobot.pigFeedRobot"].groups` (.hopper.marker, .fillLevel, .capacity); its robot spots only copy
  them for the look, so that spec is read instead.
  A silo extension (`spec_siloExtension.storage`) is added into the silo whose loadingStation/unloadingStation is in
  its `storage.loadingStations` / `unloadingStations` (keyed by station, Storage.lua:527); unconnected ones show as
  their own SILO. Headings "SILO  |  <placeable:getName()>"; empty locations are left out.
- User's milk silo (NF Marsch savegame1) = `FS25_Fed_Mods_Pack/Lager_Fluessigkeiten.xml`, a plain spec_silo.
- Class hooks dispatch through `InGameMenuStatisticsFrame.sptHandler` (cleared in `deleteMap`)
  so hooks stacked from earlier sessions never run stale code.
- Station mode ("Show Stations") filters `frame.currentAcceptedFillTypes` too.
- (v0.4.x, replaced in 0.5.0.0) The list used FRUIT TYPES / PRODUCTIONS / MISC sections; the milk silo's milk was
  buried in MISC at the bottom, which is why the user asked for per-location headings (mockup v5). The game's STORAGE
  column only counts silos, so every row's amount is our own. Tested in MP 2026-10-20 with v0.4.0.0: amounts showed
  correctly. `frame.sptLocations[section]` = the location shown in that list section. The frame's list data source functions (getNumberOfSections, getNumberOfItemsInSection,
  getTitleForSectionHeader, populateCellForItemInSection) are wrapped with Utils.overwrittenFunction and dispatch
  through sptHandler. After the game fills a cell, the amount text is overwritten with our silo or production
  liters (`g_i18n:formatVolume`). The amount element is found by attribute name (storage/fillLevel/...), or else
  the first text element that isn't the commodity name and holds "-" or a digit (cached as `cell.sptStorageText`).
  gameSource.zip's InGameMenuStatisticsFrame.lua is stripped (no prices code), so these names are unverified.
- `build.ps1` refuses to run while the game is running, even though it writes to Mods in waiting. Zip the same
  file list by hand if needed.

## Known gaps / ideas
- Gamepad shoulder-button paging cannot reach the MY SILOS tab (mouse click only).
- English only; add `translations/l10n_<lang>.xml` for more languages.
- Multiplayer not tested.
