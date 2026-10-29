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
-- connected to), bunker silos, production points, animal pens. Each location is
-- {kind, name, levels = fillTypeIndex -> liters, inputs = fillTypeIndex -> true (production inputs)}
function FarmInventory.getOwnLocations(farmId)
    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if placeableSystem == nil or farmId == nil then
        return {}
    end

    local function newLocation(kind, placeable)
        return {kind = kind, name = placeable.getName ~= nil and placeable:getName() or "", levels = {}, inputs = {}}
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

    local silos, bunkers, productions, animals = {}, {}, {}, {}
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
                local location = newLocation("production", placeable)
                addStorage(location, productionPoint.storage)
                for fillTypeIndex in pairs(productionPoint.inputFillTypeIds or {}) do
                    if not (productionPoint.outputFillTypeIds or {})[fillTypeIndex] then
                        location.inputs[fillTypeIndex] = true
                    end
                end
                table.insert(productions, location)
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

    local locations = {}
    for _, group in ipairs({silos, bunkers, productions, animals}) do
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
    -- kept in two places shows under both, each with its own amount. Locations with nothing stored are left out.
    local minLevel = FarmInventory.MIN_LEVEL
    local filtered, counts, locations, total = {}, {}, {}, 0
    for _, location in ipairs(FarmInventory.getOwnLocations(getPlayerFarmId(frame))) do
        local entries = {}
        for _, gameEntries in ipairs(full) do
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

function FarmInventory.deactivate(frame)
    if not frame.sptActive then
        return
    end
    frame.sptActive = false

    local selected = getSelectedEntry(frame)
    restoreFillTypes(frame)
    FarmInventory.setEmptyState(frame, false)
    if frame.productList ~= nil then
        frame.productList:reloadData()
    end
    selectEntry(frame, selected)

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
    FarmInventory.deactivate(frame)
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
end

function FarmInventory.onFrameClose(frame)
    FarmInventory.deactivate(frame)
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
    return string.format("%s  |  %s", FarmInventory.texts.kinds[location.kind] or "", location.name)
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

-- The cell's text element showing the commodity name (the game sets it to the fill type title)
local function findNameText(cell, title)
    local found = nil
    local function scan(element)
        for _, child in ipairs(element.elements or {}) do
            if found ~= nil then
                return
            end
            if child.setText ~= nil and child.text == title then
                found = child
                return
            end
            scan(child)
        end
    end
    scan(cell)
    return found
end

function FarmInventory.populateCellForItemInSection(frame, superFunc, list, section, index, cell, ...)
    local result = superFunc(frame, list, section, index, cell, ...)
    if not isOwnProductList(frame, list) or cell == nil then
        return result
    end

    local entries = frame.fillTypes[section]
    local entry = entries ~= nil and entries[index] or nil
    local fillTypeIndex = getEntryFillTypeIndex(entry)
    if fillTypeIndex == nil then
        return result
    end

    local location = frame.sptLocations[section]
    if location == nil then
        return result
    end
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    local title = fillType ~= nil and fillType.title or nil
    local storageText = findStorageText(cell, title)
    if storageText ~= nil then
        storageText:setText(g_i18n:formatVolume(location.levels[fillTypeIndex] or 0, 0))
    end
    -- production inputs: "Wheat (input)" in the name text the game just filled in
    if location.inputs[fillTypeIndex] and title ~= nil then
        local nameText = findNameText(cell, title)
        if nameText ~= nil then
            nameText:setText(string.format("%s %s", title, FarmInventory.texts.input))
        end
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
        input = g_i18n:getText("ui_sptInput"),
        kinds = {
            silo = g_i18n:getText("ui_sptSilo"),
            bunkerSilo = g_i18n:getText("ui_sptBunkerSilo"),
            production = g_i18n:getText("ui_sptProduction"),
            animals = g_i18n:getText("ui_sptAnimals")
        }
    }
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
