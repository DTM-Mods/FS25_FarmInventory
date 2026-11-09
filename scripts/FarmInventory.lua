-- Farm Inventory
-- Adds an "INVENTORY" tab next to PRICES in the in-game Prices menu. The tab reuses the built-in
-- prices page but lists the goods the player's farm has stored, grouped by where they are kept
-- (silos, bunker silos, production points, animal pens).
--
-- No extra paging state is added (other mods, e.g. SortableVehicleTabbing, claim index 6+).
-- While the tab is active the frame stays on SUB_CATEGORY.PRICES and frame.fillTypes (the
-- product list data, one array per section) is swapped for a filtered copy.

FarmInventory = {}
FarmInventory.TAG = "[FarmInventory]"
FarmInventory.EMPTY_STATE_HIDDEN = {"priceList", "priceListSliderBox", "fluctuationsLayoutBg", "fluctuationsContainer", "noFluctuationsText"}

local PRICES = InGameMenuStatisticsFrame ~= nil and InGameMenuStatisticsFrame.SUB_CATEGORY.PRICES or 1

local function getEntryFillTypeIndex(entry)
    if type(entry) == "number" then
        return entry
    elseif type(entry) ~= "table" then
        return nil
    end
    if type(entry.index) == "number" then
        return entry.index
    elseif type(entry.fillTypeIndex) == "number" then
        return entry.fillTypeIndex
    end
    local fillType = entry.fillType
    if type(fillType) == "number" then
        return fillType
    elseif type(fillType) == "table" and type(fillType.index) == "number" then
        return fillType.index
    end
    return nil
end

local function getPlayerFarmId(frame)
    if frame.playerFarm ~= nil and frame.playerFarm.farmId ~= nil then
        return frame.playerFarm.farmId
    end
    return g_currentMission:getFarmId()
end

-- Smallest amount that counts as stored (the game shows anything below as 0 l)
FarmInventory.MIN_LEVEL = 0.5

-- The farm's storage locations in list order: silos (silo extensions added into the silo they are
-- connected to), feeding robots, bunker silos, production points, animal pens. Each location is
FarmInventory.LIQUID_NAMES = {"MILK", "WATER", "DIESEL", "HERBICIDE", "LIQUIDFERTILIZER", "LIQUIDLIME", "LIQUIDMANURE",
    "DIGESTATE", "DEF", "METHANE", "OIL", "SYRUP", "JUICE", "WHEY", "CREAM", "VINEGAR", "BRINE", "SLURRY", "ETHANOL"}

-- true for milk, water, fuels, sprays ...: the game's LIQUID category if the map has one, else by fill type name
function FarmInventory.isLiquid(fillTypeIndex)
    local manager = g_fillTypeManager
    local categories = manager ~= nil and manager.categoryNameToFillTypes or nil
    if categories ~= nil and categories.LIQUID ~= nil and categories.LIQUID[fillTypeIndex] then
        return true
    end
    local name = manager ~= nil and manager:getFillTypeNameByIndex(fillTypeIndex) or nil
    if name == nil then
        return false
    end
    for _, part in ipairs(FarmInventory.LIQUID_NAMES) do
        if string.find(name, part, 1, true) ~= nil then
            return true
        end
    end
    return false
end

-- The fill type a feeding robot bin takes (the field names of the game's FeedingRobot class are unverified,
-- FeedingRobot.lua is not in gameSource.zip, so several are tried)
local function getSpotFillType(robot, spotIndex, spot)
    local fillTypes = spot.fillTypes
    if type(fillTypes) == "table" then
        if type(fillTypes[1]) == "number" then
            return fillTypes[1]
        end
        local lowest = nil
        for fillTypeIndex, value in pairs(fillTypes) do
            local index = type(value) == "number" and value or fillTypeIndex
            if type(index) == "number" and (lowest == nil or index < lowest) then
                lowest = index
            end
        end
        if lowest ~= nil then
            return lowest
        end
    end
    for _, name in ipairs({"fillTypeIndex", "fillType"}) do
        if type(spot[name]) == "number" then
            return spot[name]
        end
    end
    for fillTypeIndex, target in pairs(robot.fillTypeToUnloadingSpot or {}) do
        if target == spot or target == spotIndex then
            return fillTypeIndex
        end
    end
    return nil
end

-- One row per bin of the placeable's feeding robot, empty bins included: {fillTypeIndex, level, capacity}.
-- FS25_PigBarnWithRobot keeps its hoppers in its own spec (the robot's bins there only copy them for the look).
function FarmInventory.getFeedingRobotRows(placeable)
    local rows = {}
    local pigSpec = placeable["spec_FS25_PigBarnWithRobot.pigFeedRobot"]
    if pigSpec ~= nil and type(pigSpec.groups) == "table" then
        for _, group in ipairs(pigSpec.groups) do
            local hopper = group.hopper or {}
            local fillTypeIndex = hopper.marker ~= nil and g_fillTypeManager:getFillTypeIndexByName(hopper.marker) or group.foodFillType
            if fillTypeIndex ~= nil then
                table.insert(rows, {fillTypeIndex = fillTypeIndex, level = group.fillLevel or 0, capacity = group.capacity or 0})
            end
        end
        return rows
    end

    local robot = placeable.spec_husbandryFeedingRobot ~= nil and placeable.spec_husbandryFeedingRobot.feedingRobot or nil
    if robot == nil or type(robot.unloadingSpots) ~= "table" then
        return rows
    end
    for spotIndex, spot in ipairs(robot.unloadingSpots) do
        local fillTypeIndex = getSpotFillType(robot, spotIndex, spot)
        if fillTypeIndex ~= nil then
            table.insert(rows, {fillTypeIndex = fillTypeIndex, level = spot.fillLevel or 0, capacity = spot.capacity or 0})
        elseif not FarmInventory.spotDumped then
            FarmInventory.spotDumped = true
            local keys = {}
            for key, value in pairs(spot) do
                table.insert(keys, string.format("%s=%s", tostring(key), type(value)))
            end
            print(string.format("%s feeding robot bin without a known fill type, fields: %s", FarmInventory.TAG, table.concat(keys, ", ")))
        end
    end
    return rows
end

---------------------------------------------------------------------------------------------
-- Hidden locations (per player: modSettings/FS25_FarmInventory_hidden.xml, keyed by map, placeable xml and position)
---------------------------------------------------------------------------------------------

FarmInventory.HIDDEN_FILE = "FS25_FarmInventory_hidden.xml"

function FarmInventory.getPlaceableKey(placeable)
    local x, z = 0, 0
    if placeable.rootNode ~= nil and placeable.rootNode ~= 0 then
        local wx, _, wz = getWorldTranslation(placeable.rootNode)
        x, z = math.floor(wx + 0.5), math.floor(wz + 0.5)
    end
    local mapId = g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.mapId or ""
    return string.format("%s|%s|%d|%d", tostring(mapId), tostring(placeable.configFileName), x, z)
end

local function getHiddenFilename()
    return getUserProfileAppPath() .. "modSettings/" .. FarmInventory.HIDDEN_FILE
end

function FarmInventory.loadHidden()
    FarmInventory.hidden = {}
    local xmlFile = XMLFile.loadIfExists("farmInventoryHidden", getHiddenFilename())
    if xmlFile == nil then
        return
    end
    xmlFile:iterate("farmInventoryHidden.location", function(_, key)
        local locationKey = xmlFile:getString(key .. "#key")
        if locationKey ~= nil then
            FarmInventory.hidden[locationKey] = true
        end
    end)
    xmlFile:delete()
end

function FarmInventory.saveHidden()
    createFolder(getUserProfileAppPath() .. "modSettings/")
    local xmlFile = XMLFile.create("farmInventoryHidden", getHiddenFilename(), "farmInventoryHidden")
    if xmlFile == nil then
        print(FarmInventory.TAG .. " could not save the hidden list")
        return
    end
    local keys = {}
    for locationKey in pairs(FarmInventory.hidden) do
        table.insert(keys, locationKey)
    end
    table.sort(keys)
    for i, locationKey in ipairs(keys) do
        xmlFile:setString(string.format("farmInventoryHidden.location(%d)#key", i - 1), locationKey)
    end
    xmlFile:save()
    xmlFile:delete()
end

function FarmInventory.isHidden(location)
    return FarmInventory.hidden ~= nil and location.key ~= nil and FarmInventory.hidden[location.key] == true
end

-- {kind, name, key, levels = fillTypeIndex -> liters}; feeding robots also have rows (see getFeedingRobotRows)
function FarmInventory.getOwnLocations(farmId)
    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if placeableSystem == nil or farmId == nil then
        return {}
    end

    local function newLocation(kind, placeable)
        return {kind = kind, name = placeable.getName ~= nil and placeable:getName() or "", levels = {},
            key = FarmInventory.getPlaceableKey(placeable)}
    end
    local function addLevel(location, fillTypeIndex, level)
        if fillTypeIndex ~= nil and level ~= nil and level > 0 then
            location.levels[fillTypeIndex] = (location.levels[fillTypeIndex] or 0) + level
        end
    end
    local function addStorage(location, storage)
        if storage ~= nil and storage.fillLevels ~= nil then
            for fillTypeIndex, level in pairs(storage.fillLevels) do
                addLevel(location, fillTypeIndex, level)
            end
        end
    end

    local silos, robots, bunkers, productions, animals = {}, {}, {}, {}, {}
    local siloByStation = {} -- a silo's loading/unloading station -> its location
    local extensions = {}
    for _, placeable in ipairs(placeableSystem.placeables) do
        if placeable:getOwnerFarmId() == farmId then
            local siloSpec = placeable.spec_silo
            if siloSpec ~= nil then
                local location = newLocation("silo", placeable)
                for _, storage in ipairs(siloSpec.storages or {}) do
                    addStorage(location, storage)
                end
                for _, station in ipairs({siloSpec.loadingStation, siloSpec.unloadingStation}) do
                    siloByStation[station] = location
                end
                table.insert(silos, location)
            end
            if placeable.spec_siloExtension ~= nil and placeable.spec_siloExtension.storage ~= nil then
                table.insert(extensions, placeable)
            end
            local bunkerSilo = placeable.spec_bunkerSilo ~= nil and placeable.spec_bunkerSilo.bunkerSilo or nil
            if bunkerSilo ~= nil then
                -- same fill type the game shows in the bunker's info text (BunkerSilo:update)
                local fillTypeIndex = bunkerSilo.inputFillType
                if bunkerSilo.state == BunkerSilo.STATE_CLOSED or bunkerSilo.state == BunkerSilo.STATE_FERMENTED
                    or bunkerSilo.state == BunkerSilo.STATE_DRAIN then
                    fillTypeIndex = bunkerSilo.outputFillType
                end
                local location = newLocation("bunkerSilo", placeable)
                addLevel(location, fillTypeIndex, bunkerSilo.fillLevel)
                table.insert(bunkers, location)
            end
            local productionPoint = placeable.spec_productionPoint ~= nil and placeable.spec_productionPoint.productionPoint or nil
            if productionPoint ~= nil then
                -- only the goods it makes: inputs can't be taken back out (all goods if the output list is missing)
                local location = newLocation("production", placeable)
                local storage = productionPoint.storage
                local outputs = productionPoint.outputFillTypeIds
                if outputs == nil then
                    addStorage(location, storage)
                elseif storage ~= nil and storage.fillLevels ~= nil then
                    for fillTypeIndex in pairs(outputs) do
                        addLevel(location, fillTypeIndex, storage.fillLevels[fillTypeIndex])
                    end
                end
                table.insert(productions, location)
            end
            if placeable.spec_husbandryFeedingRobot ~= nil then
                local rows = FarmInventory.getFeedingRobotRows(placeable)
                if #rows > 0 then
                    local location = newLocation("feedingRobot", placeable)
                    location.rows = rows
                    for _, row in ipairs(rows) do
                        addLevel(location, row.fillTypeIndex, row.level)
                    end
                    table.insert(robots, location)
                end
            end
            if placeable.spec_husbandry ~= nil and placeable.spec_husbandry.storage ~= nil then
                local location = newLocation("animals", placeable)
                addStorage(location, placeable.spec_husbandry.storage)
                table.insert(animals, location)
            end
        end
    end

    -- a silo extension counts toward the silo whose stations it is connected to, else it shows on its own
    for _, placeable in ipairs(extensions) do
        local storage = placeable.spec_siloExtension.storage
        local location = nil
        for _, stations in ipairs({storage.loadingStations or {}, storage.unloadingStations or {}}) do
            for station in pairs(stations) do
                location = location or siloByStation[station]
            end
        end
        if location == nil then
            location = newLocation("silo", placeable)
            table.insert(silos, location)
        end
        addStorage(location, storage)
    end

    -- liquid storages (every good in them is a liquid) go right below the other silos
    local drySilos, liquidSilos = {}, {}
    for _, location in ipairs(silos) do
        local isLiquid = next(location.levels) ~= nil
        for fillTypeIndex in pairs(location.levels) do
            isLiquid = isLiquid and FarmInventory.isLiquid(fillTypeIndex)
        end
        table.insert(isLiquid and liquidSilos or drySilos, location)
    end

    local locations = {}
    for _, group in ipairs({drySilos, liquidSilos, robots, bunkers, productions, animals}) do
        for _, location in ipairs(group) do
            table.insert(locations, location)
        end
    end
    return locations
end

-- fillTypeIndex -> liters over all of the farm's locations
function FarmInventory.getOwnFillLevels(farmId)
    local levels = {}
    for _, location in ipairs(FarmInventory.getOwnLocations(farmId)) do
        for fillTypeIndex, level in pairs(location.levels) do
            levels[fillTypeIndex] = (levels[fillTypeIndex] or 0) + level
        end
    end
    return levels
end

---------------------------------------------------------------------------------------------
-- Filtered list data
---------------------------------------------------------------------------------------------

-- False once the game replaced or rebuilt frame.fillTypes while the tab was active
local function isFilterIntact(frame)
    local filtered = frame.sptFilteredFillTypes
    if filtered == nil or frame.fillTypes ~= filtered then
        return false
    end
    for section, count in ipairs(frame.sptFilteredCounts) do
        if filtered[section] == nil or #filtered[section] ~= count then
            return false
        end
    end
    return true
end

local function getSelectedEntry(frame)
    local list = frame.productList
    if list == nil or frame.fillTypes == nil or frame.sellingStationMode then
        return nil
    end
    local entries = frame.fillTypes[list.selectedSectionIndex or 1]
    return entries ~= nil and entries[list.selectedIndex or 1] or nil
end

-- Selects the given entry, or the first item if it is not in the current list
local function selectEntry(frame, entry)
    local list = frame.productList
    if list == nil or frame.sellingStationMode then
        return
    end
    local firstSection = nil
    for section, entries in ipairs(frame.fillTypes) do
        for index, candidate in ipairs(entries) do
            if candidate == entry then
                list:setSelectedItem(section, index, true, true)
                return
            end
        end
        if firstSection == nil and #entries > 0 then
            firstSection = section
        end
    end
    if firstSection ~= nil then
        list:setSelectedItem(firstSection, 1, true, true)
    end
end

local function restoreFillTypes(frame)
    if isFilterIntact(frame) then
        frame.fillTypes = frame.sptFullFillTypes
    end
    frame.sptFilteredFillTypes = nil
    frame.sptFilteredCounts = nil
    frame.sptFullFillTypes = nil
    frame.sptLocations = nil
end

function FarmInventory.applyFilter(frame)
    if frame.sptFilteredFillTypes ~= nil then
        restoreFillTypes(frame)
    end
    local full = frame.fillTypes
    if full == nil then
        return 0
    end

    -- one section per storage location with a heading "SILO | <name>"; goods keep the game's list order, and a good
    -- kept in two places shows under both, each with its own amount. Locations with nothing stored are left out,
    -- except feeding robots, which list every bin.
    local minLevel = FarmInventory.MIN_LEVEL
    -- hidden locations are left out, unless SHOW HIDDEN is on
    local filtered, counts, locations, total = {}, {}, {}, 0
    local hiddenCount = 0
    for _, location in ipairs(FarmInventory.getOwnLocations(getPlayerFarmId(frame))) do
        local entries = {}
        if FarmInventory.isHidden(location) then
            hiddenCount = hiddenCount + 1
            if not frame.sptShowHidden then
                location.rows = {}
                location.skip = true
            end
        end
        if location.rows ~= nil then
            -- feeding robot: every bin in bin order, empty ones too; a feed the price list doesn't have uses its fill type
            for _, row in ipairs(location.rows) do
                local entry = nil
                for _, gameEntries in ipairs(full) do
                    for _, gameEntry in ipairs(gameEntries) do
                        if entry == nil and getEntryFillTypeIndex(gameEntry) == row.fillTypeIndex then
                            entry = gameEntry
                        end
                    end
                end
                table.insert(entries, entry or g_fillTypeManager:getFillTypeByIndex(row.fillTypeIndex))
            end
        end
        for _, gameEntries in ipairs((location.rows == nil and not location.skip) and full or {}) do
            for _, entry in ipairs(gameEntries) do
                local fillTypeIndex = getEntryFillTypeIndex(entry)
                if fillTypeIndex ~= nil and (location.levels[fillTypeIndex] or 0) >= minLevel then
                    table.insert(entries, entry)
                end
            end
        end
        if #entries > 0 then
            table.insert(filtered, entries)
            table.insert(locations, location)
            counts[#filtered] = #entries
            total = total + #entries
        end
    end

    frame.sptFullFillTypes = full
    frame.sptFilteredFillTypes = filtered
    frame.sptFilteredCounts = counts
    frame.sptLocations = locations
    frame.sptHiddenCount = hiddenCount
    frame.fillTypes = filtered
    return total
end

function FarmInventory.setEmptyState(frame, isEmpty)
    if isEmpty == (frame.sptEmptyShown == true) then
        return
    end
    frame.sptEmptyShown = isEmpty

    if isEmpty then
        frame.sptSavedVisibility = {}
        for _, id in ipairs(FarmInventory.EMPTY_STATE_HIDDEN) do
            local element = frame[id]
            if element ~= nil then
                frame.sptSavedVisibility[id] = element.visible
                element:setVisible(false)
            end
        end
        if frame.noSellpointsText ~= nil then
            frame.sptSavedNoSellpoints = {text = frame.noSellpointsText.text, visible = frame.noSellpointsText.visible}
            frame.noSellpointsText:setText(FarmInventory.texts.noGoods)
            frame.noSellpointsText:setVisible(true)
        end
    else
        for id, visible in pairs(frame.sptSavedVisibility or {}) do
            if frame[id] ~= nil then
                frame[id]:setVisible(visible)
            end
        end
        local saved = frame.sptSavedNoSellpoints
        if saved ~= nil and frame.noSellpointsText ~= nil then
            frame.noSellpointsText:setText(saved.text or "")
            frame.noSellpointsText:setVisible(saved.visible)
        end
        frame.sptSavedVisibility = nil
        frame.sptSavedNoSellpoints = nil
    end
end

function FarmInventory.refresh(frame)
    local selected = getSelectedEntry(frame)
    local total = FarmInventory.applyFilter(frame)
    if frame.productList ~= nil then
        frame.productList:reloadData()
    end
    selectEntry(frame, selected)
    FarmInventory.setEmptyState(frame, total == 0 and not frame.sellingStationMode)
end

---------------------------------------------------------------------------------------------
-- HIDE / SHOW HIDDEN buttons in the bottom bar (added to the frame's own menuButtonInfo while the tab is active)
---------------------------------------------------------------------------------------------

FarmInventory.BUTTON_ACTIONS = {"MENU_EXTRA_2", "MENU_EXTRA_3", "MENU_EXTRA_4"}

local function getSelectedLocation(frame)
    local list = frame.productList
    if list == nil or frame.sellingStationMode or frame.sptLocations == nil or not isFilterIntact(frame) then
        return nil
    end
    return frame.sptLocations[list.selectedSectionIndex or 1]
end

function FarmInventory.toggleSelectedHidden(frame)
    local location = getSelectedLocation(frame)
    if location == nil or location.key == nil then
        return
    end
    FarmInventory.hidden[location.key] = not FarmInventory.isHidden(location) or nil
    FarmInventory.saveHidden()
    FarmInventory.refresh(frame)
    FarmInventory.updateButtons(frame)
end

function FarmInventory.toggleShowHidden(frame)
    frame.sptShowHidden = not frame.sptShowHidden
    FarmInventory.refresh(frame)
    FarmInventory.updateButtons(frame)
end

-- The statistics frame keeps one button list PER SUB-TAB: menuButtonInfo[subCategory] (its getMenuButtonInfo returns
-- menuButtonInfo[subCategoryPaging:getState()]; FS25_SortableVehicleTabbing adds [6]). Our buttons go in the PRICES list.
local function getPricesButtonList(frame)
    local all = frame.menuButtonInfo
    local list = type(all) == "table" and all[PRICES] or nil
    return type(list) == "table" and list or nil
end

-- markDirty = false while the menu is closing: the menu clears its button actions itself then
function FarmInventory.removeButtons(frame, markDirty)
    if frame.sptButtons == nil then
        return
    end
    for _, infos in pairs({frame.sptButtonList or false, getPricesButtonList(frame) or false, frame.menuButtonInfo or false}) do
        for i = (infos and #infos or 0), 1, -1 do
            local info = infos[i]
            if type(info) == "table" and info.sptOwner == FarmInventory then
                table.remove(infos, i)
            end
        end
    end
    frame.sptButtons = nil
    frame.sptButtonList = nil
    if markDirty ~= false then
        frame:setMenuButtonInfoDirty()
    end
end

function FarmInventory.updateButtons(frame)
    local infos = getPricesButtonList(frame)
    if infos == nil or frame.sellingStationMode then
        FarmInventory.removeButtons(frame)
        return
    end

    local location = getSelectedLocation(frame)
    local hideText = nil
    if location ~= nil then
        hideText = FarmInventory.isHidden(location) and FarmInventory.texts.unhide or FarmInventory.texts.hide
    end
    local showText = nil
    if (frame.sptHiddenCount or 0) > 0 then
        showText = string.format("%s (%d)", frame.sptShowHidden and FarmInventory.texts.hideHidden or FarmInventory.texts.showHidden,
            frame.sptHiddenCount)
    end

    -- rebuild only when the game replaced the button list or a text changed
    local buttons = frame.sptButtons
    local present = buttons ~= nil and frame.sptButtonList == infos
    for _, info in ipairs(buttons or {}) do
        local found = false
        for _, other in ipairs(infos) do
            found = found or other == info
        end
        present = present and found
    end
    if present and buttons.hideText == hideText and buttons.showText == showText then
        return
    end
    FarmInventory.removeButtons(frame)

    local used = {}
    for _, info in ipairs(infos) do
        if info.inputAction ~= nil then
            used[info.inputAction] = true
        end
    end
    local function nextAction()
        for _, name in ipairs(FarmInventory.BUTTON_ACTIONS) do
            local action = InputAction[name]
            if action ~= nil and not used[action] then
                used[action] = true
                return action
            end
        end
        return nil
    end

    buttons = {hideText = hideText, showText = showText}
    for _, button in ipairs({{hideText, FarmInventory.toggleSelectedHidden}, {showText, FarmInventory.toggleShowHidden}}) do
        local action = button[1] ~= nil and nextAction() or nil
        if action ~= nil then
            local toggle = button[2]
            table.insert(buttons, {inputAction = action, text = button[1], sptOwner = FarmInventory,
                callback = function() toggle(frame) end})
        end
    end
    for _, info in ipairs(buttons) do
        table.insert(infos, info)
    end
    frame.sptButtons = buttons
    frame.sptButtonList = infos
    frame:setMenuButtonInfoDirty()
end

---------------------------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------------------------

function FarmInventory.activate(frame)
    if frame.sellingStationMode and frame.onButtonChangeSellingStationMode ~= nil then
        frame:onButtonChangeSellingStationMode()
    end

    local pricesTab = frame.subCategoryTabs[PRICES]
    if not frame.sptActive and frame.categoryHeaderText ~= nil then
        frame.sptSavedHeaderText = frame.categoryHeaderText.text
    end
    frame.sptActive = true

    -- run the game's own PRICES tab handler so the page is shown exactly as usual
    if pricesTab ~= nil and pricesTab.sptSaved ~= nil and pricesTab.sptSaved.onClickCallback ~= nil then
        pricesTab.sptSaved.onClickCallback(frame, pricesTab)
    else
        frame.subCategoryPaging:setState(PRICES, true)
    end

    FarmInventory.refresh(frame)
    if frame.categoryHeaderText ~= nil then
        frame.categoryHeaderText:setText(FarmInventory.texts.label)
    end
end

-- closing = true when the whole menu is closing (Esc). Then nothing is rebuilt and no list/selection/button
-- events are fired into the closing menu: the full list is put back silently and redrawn on the next open.
function FarmInventory.deactivate(frame, closing)
    if not frame.sptActive then
        return
    end
    frame.sptActive = false
    FarmInventory.removeButtons(frame, not closing)

    local selected = getSelectedEntry(frame)
    restoreFillTypes(frame)
    FarmInventory.setEmptyState(frame, false)
    if closing then
        -- keep the list's selection inside the full list without firing a selection change
        local list = frame.productList
        if list ~= nil and frame.fillTypes ~= nil then
            local section, index = 1, 1
            for s, entries in ipairs(frame.fillTypes) do
                for i, candidate in ipairs(entries) do
                    if candidate == selected then
                        section, index = s, i
                    end
                end
            end
            list.selectedSectionIndex = section
            list.selectedIndex = index
        end
        frame.sptReloadOnOpen = true
    else
        if frame.productList ~= nil then
            frame.productList:reloadData()
        end
        selectEntry(frame, selected)
    end

    if frame.sptSavedHeaderText ~= nil and frame.categoryHeaderText ~= nil and frame.subCategoryPaging:getState() == PRICES then
        frame.categoryHeaderText:setText(frame.sptSavedHeaderText)
    end
    frame.sptSavedHeaderText = nil
end

---------------------------------------------------------------------------------------------
-- Tab button
---------------------------------------------------------------------------------------------

-- Saves an element's own (raw) fields once so teardown can put them back exactly
local function saveFields(element, names)
    if element == nil or element.sptSaved ~= nil then
        return
    end
    element.sptSaved = {}
    element.sptSavedNames = names
    for _, name in ipairs(names) do
        element.sptSaved[name] = rawget(element, name)
    end
end

local function restoreFields(element)
    if element == nil or element.sptSaved == nil then
        return
    end
    for _, name in ipairs(element.sptSavedNames) do
        element[name] = element.sptSaved[name]
    end
    element.sptSaved = nil
    element.sptSavedNames = nil
end

local function fitTabWidth(tab)
    if not tab.textAutoWidth then
        return
    end
    setTextBold(tab.textBold)
    local textWidth = getTextWidth(tab.textSize, tab.sourceText or tab.text or "") + 0.001
    setTextBold(false)
    local iconSize = tab.getIconSize ~= nil and tab:getIconSize() or 0
    local width = iconSize + textWidth + (tab.fitExtraWidth or 0)
    tab:setSize(width, tab.size[2], true)
    local background = tab:getDescendantByName("background")
    if background ~= nil then
        background:setSize(width, background.size[2])
    end
end

function FarmInventory.setup(frame)
    if frame.subCategoryTabs == nil or frame.subCategoryPaging == nil then
        return
    end
    local pricesTab = frame.subCategoryTabs[PRICES]
    if pricesTab == nil then
        return
    end
    if frame.sptTab ~= nil then
        if frame.sptTab.sptOwner == FarmInventory then
            return
        end
        FarmInventory.teardown(frame) -- left over from an earlier session
    end

    local tab = pricesTab:clone(pricesTab.parent, false, true, true)
    tab.sptSaved = nil
    tab.sptOwner = FarmInventory
    tab:setTarget(frame, tab.target, false)
    tab:setText(FarmInventory.texts.label)
    fitTabWidth(tab)

    local function isOwnTabSelected()
        return frame.sptActive == true and frame.subCategoryPaging:getState() == PRICES
    end
    local function isPricesTabSelected()
        return frame.sptActive ~= true and frame.subCategoryPaging:getState() == PRICES
    end

    tab.onClickCallback = function()
        FarmInventory.activate(frame)
    end
    tab.getIsSelected = isOwnTabSelected
    local tabBackground = tab:getDescendantByName("background")
    if tabBackground ~= nil then
        tabBackground.sptSaved = nil
        tabBackground.getIsSelected = isOwnTabSelected
    end

    saveFields(pricesTab, {"onClickCallback", "getIsSelected"})
    local onClickPrices = pricesTab.sptSaved.onClickCallback
    pricesTab.onClickCallback = function(...)
        FarmInventory.deactivate(frame)
        if onClickPrices ~= nil then
            return onClickPrices(...)
        end
    end
    pricesTab.getIsSelected = isPricesTabSelected
    local pricesBackground = pricesTab:getDescendantByName("background")
    if pricesBackground ~= nil then
        saveFields(pricesBackground, {"getIsSelected"})
        pricesBackground.getIsSelected = isPricesTabSelected
    end

    frame.sptTab = tab
    if frame.subCategoryBox ~= nil then
        frame.subCategoryBox:invalidateLayout()
        frame.subCategoryBox:updateAbsolutePosition()
    end
end

function FarmInventory.teardown(frame)
    FarmInventory.deactivate(frame, true)
    local pricesTab = frame.subCategoryTabs ~= nil and frame.subCategoryTabs[PRICES] or nil
    if pricesTab ~= nil then
        restoreFields(pricesTab)
        restoreFields(pricesTab:getDescendantByName("background"))
    end
    if frame.sptTab ~= nil then
        frame.sptTab:delete()
        frame.sptTab = nil
        if frame.subCategoryBox ~= nil then
            frame.subCategoryBox:invalidateLayout()
        end
    end
end

---------------------------------------------------------------------------------------------
-- Frame hooks (dispatch through InGameMenuStatisticsFrame.sptHandler so hooks installed by an
-- earlier session never run stale code, and do nothing in savegames without this mod)
---------------------------------------------------------------------------------------------

function FarmInventory.onFrameOpen(frame)
    FarmInventory.setup(frame)
    if frame.sptReloadOnOpen then
        frame.sptReloadOnOpen = nil
        if not frame.sptActive and frame.productList ~= nil then
            frame.productList:reloadData() -- drop the INVENTORY rows left from the last close
        end
    end
end

function FarmInventory.onFrameClose(frame)
    FarmInventory.deactivate(frame, true)
end

function FarmInventory.onUpdate(frame)
    if not frame.sptActive then
        return
    end
    if frame.subCategoryPaging:getState() ~= PRICES then
        FarmInventory.deactivate(frame)
        return
    end
    if not isFilterIntact(frame) then
        FarmInventory.refresh(frame) -- the game rebuilt the product list
    end
    FarmInventory.updateButtons(frame)
    if frame.categoryHeaderText ~= nil and frame.categoryHeaderText.text ~= FarmInventory.texts.label then
        frame.categoryHeaderText:setText(FarmInventory.texts.label)
    end
end

-- Station mode lists the commodities a station accepts; limit those to stored goods as well
function FarmInventory.onUpdateAcceptedFillTypes(frame)
    local accepted = frame.currentAcceptedFillTypes
    if not frame.sptActive or accepted == nil then
        return
    end
    local levels = FarmInventory.getOwnFillLevels(getPlayerFarmId(frame))
    for i = #accepted, 1, -1 do
        local fillTypeIndex = getEntryFillTypeIndex(accepted[i])
        if fillTypeIndex ~= nil and (levels[fillTypeIndex] or 0) <= 0 then
            table.remove(accepted, i)
        end
    end
    if frame.priceList ~= nil then
        frame.priceList:reloadData()
    end
end

---------------------------------------------------------------------------------------------
-- Product list data source (the frame is the productList's data source)
---------------------------------------------------------------------------------------------

local function isOwnProductList(frame, list)
    return frame.sptActive and list ~= nil and list == frame.productList and not frame.sellingStationMode
        and isFilterIntact(frame)
end

function FarmInventory.getNumberOfSections(frame, superFunc, list, ...)
    if isOwnProductList(frame, list) then
        return #frame.fillTypes
    end
    return superFunc(frame, list, ...)
end

function FarmInventory.getNumberOfItemsInSection(frame, superFunc, list, section, ...)
    if isOwnProductList(frame, list) then
        local entries = frame.fillTypes[section]
        return entries ~= nil and #entries or 0
    end
    return superFunc(frame, list, section, ...)
end

-- Each section is a storage location: "SILO  |  Farm Silo"
function FarmInventory.getTitleForSectionHeader(frame, superFunc, list, section, ...)
    local location = isOwnProductList(frame, list) and frame.sptLocations[section] or nil
    if location == nil then
        return superFunc(frame, list, section, ...)
    end
    local title = string.format("%s  |  %s", FarmInventory.texts.kinds[location.kind] or "", location.name)
    if FarmInventory.isHidden(location) then
        title = string.format("%s  (%s)", title, FarmInventory.texts.hiddenTag)
    end
    return title
end

local STORAGE_ATTRIBUTES = {"storage", "fillLevel", "storageAmount", "amount", "stock", "quantity"}

-- The cell's text element that shows the stored amount: a known attribute name, else the text
-- element (other than the commodity name) that the game filled with "-" or a number
local function findStorageText(cell, title)
    if cell.sptStorageText ~= nil then
        return cell.sptStorageText
    end
    if cell.getAttribute ~= nil then
        for _, name in ipairs(STORAGE_ATTRIBUTES) do
            local element = cell:getAttribute(name)
            if element ~= nil and element.setText ~= nil then
                cell.sptStorageText = element
                return element
            end
        end
    end

    local found = nil
    local function scan(element)
        for _, child in ipairs(element.elements or {}) do
            if found ~= nil then
                return
            end
            local text = child.text
            if child.setText ~= nil and type(text) == "string" and text ~= title
                and (text == "-" or text:find("%d") ~= nil) then
                found = child
                return
            end
            scan(child)
        end
    end
    scan(cell)
    cell.sptStorageText = found
    return found
end

-- Feeding robot rows show no prices: every text but the name and the amount is cleared
local function clearPriceTexts(cell, keep)
    for _, child in ipairs(cell.elements or {}) do
        if child.setText ~= nil and type(child.text) == "string" and not keep[child] then
            child:setText("")
        end
        clearPriceTexts(child, keep)
    end
end

function FarmInventory.populateCellForItemInSection(frame, superFunc, list, section, index, cell, ...)
    if not isOwnProductList(frame, list) or cell == nil then
        return superFunc(frame, list, section, index, cell, ...)
    end
    local location = frame.sptLocations[section]
    local result = nil
    if location ~= nil and location.rows ~= nil then
        -- a feed the game never prices may trip its price code; the amount is written anyway
        local ok, value = pcall(superFunc, frame, list, section, index, cell, ...)
        result = ok and value or nil
    else
        result = superFunc(frame, list, section, index, cell, ...)
    end

    local entries = frame.fillTypes[section]
    local entry = entries ~= nil and entries[index] or nil
    local fillTypeIndex = getEntryFillTypeIndex(entry)
    if fillTypeIndex == nil then
        return result
    end

    if location == nil then
        return result
    end
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    local title = fillType ~= nil and fillType.title or nil
    local storageText = findStorageText(cell, title)
    local row = location.rows ~= nil and location.rows[index] or nil
    if row ~= nil then
        -- "107,103 / 120,000 l", no prices
        local keep = {}
        if storageText ~= nil then
            storageText:setText(string.format("%s / %s", g_i18n:formatNumber(row.level, 0), g_i18n:formatVolume(row.capacity, 0)))
            keep[storageText] = true
        end
        local function keepName(element)
            for _, child in ipairs(element.elements or {}) do
                if child.text == title then
                    keep[child] = true
                end
                keepName(child)
            end
        end
        keepName(cell)
        clearPriceTexts(cell, keep)
    elseif storageText ~= nil then
        storageText:setText(g_i18n:formatVolume(location.levels[fillTypeIndex] or 0, 0))
    end
    return result
end

local function installFrameHooks()
    local frameClass = InGameMenuStatisticsFrame
    if frameClass.sptHooksInstalled then
        return
    end
    frameClass.sptHooksInstalled = true

    local function dispatch(name)
        return function(frame, ...)
            local handler = frameClass.sptHandler
            if handler ~= nil then
                handler[name](frame, ...)
            end
        end
    end
    frameClass.onFrameOpen = Utils.appendedFunction(frameClass.onFrameOpen, dispatch("onFrameOpen"))
    frameClass.onFrameClose = Utils.prependedFunction(frameClass.onFrameClose, dispatch("onFrameClose"))
    frameClass.update = Utils.appendedFunction(frameClass.update, dispatch("onUpdate"))
    frameClass.updateAcceptedFillTypes = Utils.appendedFunction(frameClass.updateAcceptedFillTypes, dispatch("onUpdateAcceptedFillTypes"))

    -- list data source functions: the handler gets the original function to call through
    for _, name in ipairs({"getNumberOfSections", "getNumberOfItemsInSection", "getTitleForSectionHeader", "populateCellForItemInSection"}) do
        if frameClass[name] ~= nil then
            frameClass[name] = Utils.overwrittenFunction(frameClass[name], function(frame, superFunc, ...)
                local handler = frameClass.sptHandler
                if handler ~= nil then
                    return handler[name](frame, superFunc, ...)
                end
                return superFunc(frame, ...)
            end)
        else
            print(string.format("%s InGameMenuStatisticsFrame.%s not found, PRODUCTIONS section may not show", FarmInventory.TAG, name))
        end
    end
end

---------------------------------------------------------------------------------------------
-- Mod event listener
---------------------------------------------------------------------------------------------

function FarmInventory:loadMap()
    FarmInventory.texts = {
        label = g_i18n:getText("ui_sptTabLabel"),
        noGoods = g_i18n:getText("ui_sptNoGoods"),
        kinds = {
            silo = g_i18n:getText("ui_sptSilo"),
            bunkerSilo = g_i18n:getText("ui_sptBunkerSilo"),
            feedingRobot = g_i18n:getText("ui_sptFeedingRobot"),
            production = g_i18n:getText("ui_sptProduction"),
            animals = g_i18n:getText("ui_sptAnimals")
        },
        hide = g_i18n:getText("ui_sptHide"),
        unhide = g_i18n:getText("ui_sptUnhide"),
        showHidden = g_i18n:getText("ui_sptShowHidden"),
        hideHidden = g_i18n:getText("ui_sptHideHidden"),
        hiddenTag = g_i18n:getText("ui_sptHiddenTag")
    }
    FarmInventory.loadHidden()
    InGameMenuStatisticsFrame.sptHandler = FarmInventory
end

function FarmInventory:deleteMap()
    InGameMenuStatisticsFrame.sptHandler = nil
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageStatistics or nil
    if frame ~= nil then
        FarmInventory.teardown(frame)
    end
end

if InGameMenuStatisticsFrame ~= nil then
    installFrameHooks()
    addModEventListener(FarmInventory)
else
    print(FarmInventory.TAG .. " InGameMenuStatisticsFrame not available, tab disabled")
end
