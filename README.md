<p align="center">
  <a href="https://github.com/DTM-Mods"><img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/dtm-header.jpg" alt="DTM Mods by PropaineX & Fennell" width="100%"></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/icons/FS25_FarmInventory.png" alt="Farm Inventory Plus icon" width="128">
</p>

<h1 align="center">Farm Inventory Plus</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Farming%20Simulator-25-2E6B4F" alt="Farming Simulator 25">
  <a href="https://github.com/DTM-Mods/FS25_FarmInventory/releases/latest"><img src="https://img.shields.io/github/v/release/DTM-Mods/FS25_FarmInventory?label=version&color=D9A441" alt="Latest version"></a>
  <a href="https://github.com/DTM-Mods"><img src="https://img.shields.io/badge/DTM-Mods-143326" alt="DTM Mods"></a>
</p>

<p align="center">
  <b>Everything your farm has stored, in one INVENTORY tab next to PRICES.</b><br>
  <sub>by PropaineX</sub>
</p>

<p align="center">
  <a href="https://github.com/DTM-Mods/FS25_FarmInventory/releases/latest"><img src="https://img.shields.io/badge/Download-latest%20release-D9A441?style=for-the-badge&logo=github&logoColor=143326&labelColor=E9C77A" alt="Download the latest release"></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/features.jpg" alt="Features" width="100%">
</p>

Farming Simulator 25 mod by PropaineX. Formerly "My Silo Prices Tab" (FS25_MySiloPricesTab).

Adds an **INVENTORY** tab next to PRICES in the in-game Prices menu. It lists the goods your farm has stored,
grouped by where they are kept, with the normal market info (stations, prices, price history):

- **SILO | name**: each silo; silo extensions are added into the silo they are connected to. Liquid storage (milk, water, diesel and so on) comes right after the dry silos
- **FEEDING ROBOT | name**: every bin of a feeding robot as stored / capacity (also the Pig Barn With Feeding Robot hoppers)
- **BUNKER SILO | name**
- **PRODUCTION | name**: the goods it makes (inputs are not listed)
- **ANIMALS | name**: what is in the animal pen's storage (milk, manure, ...)

**HIDE** a whole location you don't want to see, and **SHOW HIDDEN** to bring hidden ones back. Your hidden list is saved per player.

At a silo's fill trigger, the fill type list only shows goods that are actually in stock.

**Buttons** (no in-world hotkeys: everything is in the INVENTORY tab of the Esc menu, bottom bar):

| Action | Game input |
|---|---|
| Hide / unhide the selected location | Menu Extra 2 (keyboard and controller as bound in Controls) |
| Show / hide hidden locations | Menu Extra 3 |

If another mod already uses one of these, the next free one (up to Menu Extra 4) is used.

**Languages**: the mod description is in all 27 game languages. The in-game text (tab and buttons) is English for now.

See [PATCH_NOTES.md](PATCH_NOTES.md) for what changed in each version.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/installation.jpg" alt="Installation" width="100%">
</p>

Download `FS25_FarmInventory.zip` from the [latest release](https://github.com/DTM-Mods/FS25_FarmInventory/releases/latest) and put it in `Documents/My Games/FarmingSimulator2025/mods`, without unzipping or renaming it. In multiplayer, the server and every player need the same version.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/license.jpg" alt="License" width="100%">
</p>

MIT, see [LICENSE](LICENSE).

<details>
<summary><b>For developers</b>: files, building and tests</summary>

### Building

`powershell -ExecutionPolicy Bypass -File tools\build.ps1` (game must be closed) makes `FS25_FarmInventory.zip`
in `Testing_local`.

The version is in `modDesc.xml`; [PATCH_NOTES.md](PATCH_NOTES.md) has the history.

`modDesc.xml` uses descVersion 116 (game 1.25.1.0; the GIANTS TestRunner 0.9.24 rejects older values). Check the
`ModDesc Version` line in the game's `log.txt` after a game update.

</details>

---

<p align="center">
  <a href="https://github.com/DTM-Mods"><img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/dtm-intro.gif" alt="DTM Mods by PropaineX & Fennell" width="420"></a><br>
  <sub>Part of <a href="https://github.com/DTM-Mods">DTM Mods</a> (Designed To Manage) by PropaineX & Fennell</sub><br><br>
  <a href="https://ko-fi.com/dtmmods"><img src="https://img.shields.io/badge/Ko--fi-support%20DTM%20Mods-1F4D3A?logo=kofi&logoColor=F4F1E8" alt="Support DTM Mods on Ko-fi"></a>
  <a href="https://www.paypal.com/donate/?business=dtmmods%40gmail.com&amp;no_recurring=0&amp;item_name=DTM+Mods&amp;currency_code=USD"><img src="https://img.shields.io/badge/PayPal-donate-1F4D3A?logo=paypal&logoColor=F4F1E8" alt="Donate to DTM Mods with PayPal"></a>
</p>
