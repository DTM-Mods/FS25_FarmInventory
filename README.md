# Farm Inventory Pro Edition (FS25_FarmInventory)

Farming Simulator 25 mod by PropaineX. Formerly "My Silo Prices Tab" (FS25_MySiloPricesTab).

Adds an **INVENTORY** tab next to PRICES in the in-game Prices menu. It lists the goods your farm has stored,
grouped by where they are kept, with the normal market info (stations, prices, price history):

- **SILO | name**: each silo; silo extensions are added into the silo they are connected to
- **BUNKER SILO | name**
- **PRODUCTION | name**: the goods it makes (inputs are not listed)
- **ANIMALS | name**: what is in the animal pen's storage (milk, manure, ...)

At a silo's fill trigger, the fill type list only shows goods that are actually in stock.

## Build
`powershell -ExecutionPolicy Bypass -File tools\build.ps1` (game must be closed) makes `FS25_FarmInventory.zip`
in `Testing_local`.

Version 0.5.0.0: per-location list, not yet tested in game.
