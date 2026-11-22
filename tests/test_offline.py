"""Offline tests of FS25_FarmInventory: loads the scripts named in modDesc.xml into Lua 5.1 (lupa) with a
stubbed game engine and fake GUI element trees, then exercises the mod. Every test gets a fresh Lua state.
Usage: python tests/test_offline.py        (needs: pip install lupa)   exit code 0 = all passed"""
import os
import re
import sys
import xml.etree.ElementTree as ET

import lupa.lua51 as lua51

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# GIANTS Lua knows `continue`; same transformation as .github/ci/fs25_mod.py (line numbers stay)
CONTINUE_RE = re.compile(r"(?<![\w.:'\"])continue(?![\w])")

MOD_DESC = ET.parse(os.path.join(PROJ, "modDesc.xml")).getroot()
SCRIPTS = [e.get("filename") for e in MOD_DESC.iter("sourceFile")]
TEXTS = {e.get("name"): e.get("text")
         for e in ET.parse(os.path.join(PROJ, "translations", "l10n_en.xml")).getroot().iter("text")}

# ----------------------------------------------------------------------------------------------- engine stubs
STUBS = r'''
LOG = {}
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    LOG[#LOG + 1] = table.concat(parts, "\t")
end
function logHas(s)
    for _, line in ipairs(LOG) do if line:find(s, 1, true) then return true end end
    return false
end
function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected <%s>, got <%s>", what or "value", tostring(expected), tostring(actual)), 2)
    end
end
function ok(value, what) if not value then error(what or "expected a true value", 2) end end
CALLS = {}
function note(name) CALLS[name] = (CALLS[name] or 0) + 1 end
function calls(name) return CALLS[name] or 0 end

Utils = {
    appendedFunction = function(old, new) return function(...) if old ~= nil then old(...) end return new(...) end end,
    prependedFunction = function(old, new) return function(...) new(...) if old ~= nil then return old(...) end end end,
    overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end,
}
function table.removeElement(t, element)
    for i, v in ipairs(t) do if v == element then table.remove(t, i) return true end end
    return false
end
LISTENERS = {}
function addModEventListener(listener) table.insert(LISTENERS, listener) end
function fire(name, ...)
    for _, listener in ipairs(LISTENERS) do if listener[name] ~= nil then listener[name](listener, ...) end end
end

-- texts: an unknown key is an error, so a text the script asks for must be in l10n_en.xml
local function formatNumber(n)
    local s = string.format("%.0f", n)
    local k = 1
    while k > 0 do s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") end
    return s
end
g_i18n = {
    getText = function(self, name) local v = TR[name] if v == nil then error("missing text " .. name) end return v end,
    formatNumber = function(self, n) return formatNumber(n) end,
    formatVolume = function(self, n) return formatNumber(n) .. " l" end,
}
InputAction = {MENU_BACK = "MENU_BACK", MENU_EXTRA_1 = "MENU_EXTRA_1", MENU_EXTRA_2 = "MENU_EXTRA_2",
    MENU_EXTRA_3 = "MENU_EXTRA_3", MENU_EXTRA_4 = "MENU_EXTRA_4"}
BunkerSilo = {STATE_FILL = 0, STATE_CLOSED = 1, STATE_FERMENTED = 2, STATE_DRAIN = 3}
function setTextBold() end
function getTextWidth(size, text) return size * #text end

-- fill types
FT = {}
g_fillTypeManager = {fillTypes = {}, categoryNameToFillTypes = {LIQUID = {}}}
for i, name in ipairs({"WHEAT", "BARLEY", "CANOLA", "MILK", "WATER", "SILAGE", "CHAFF", "FLOUR", "TMR", "HAY"}) do
    FT[name] = i
    g_fillTypeManager.fillTypes[i] = {index = i, name = name, title = name:sub(1, 1) .. name:sub(2):lower()}
end
g_fillTypeManager.categoryNameToFillTypes.LIQUID[FT.MILK] = true     -- WATER is only a liquid by its name
function g_fillTypeManager:getFillTypeByIndex(i) return self.fillTypes[i] end
function g_fillTypeManager:getFillTypeNameByIndex(i) return self.fillTypes[i] ~= nil and self.fillTypes[i].name or nil end
function g_fillTypeManager:getFillTypeIndexByName(name) return FT[name] end
function ft(name) return g_fillTypeManager.fillTypes[FT[name]] end

-- mission, placeables
g_currentMission = {missionInfo = {mapId = "MapUS"}, placeableSystem = {placeables = {}}, getFarmId = function() return 1 end}
POS = {}
function getWorldTranslation(node) return POS[node][1], 0, POS[node][2] end
function placeable(t)
    local node = #g_currentMission.placeableSystem.placeables + 100
    POS[node] = {t.x or 0, t.z or 0}
    local name = t.name
    t.rootNode, t.configFileName, t.farm = node, t.xml or (name .. ".xml"), t.farm or 1
    t.getOwnerFarmId = function(self) return self.farm end
    t.getName = function() return name end
    table.insert(g_currentMission.placeableSystem.placeables, t)
    return t
end
function storage(levels) return {fillLevels = levels} end

-- XMLFile kept in memory: XML_STORE[filename] = list of location keys
XML_STORE = {}
function getUserProfileAppPath() return "profile/" end
function createFolder(path) note("createFolder") end
XMLFile = {}
function XMLFile.loadIfExists(name, filename)
    local keys = XML_STORE[filename]
    if keys == nil then return nil end
    return {
        iterate = function(self, base, fn) for i = 1, #keys do fn(i, string.format("%s(%d)", base, i - 1)) end end,
        getString = function(self, key) return keys[tonumber(key:match("%((%d+)%)#key$")) + 1] end,
        delete = function() end,
    }
end
function XMLFile.create(name, filename, root)
    local keys = {}
    return {
        setString = function(self, key, value) keys[tonumber(key:match("%((%d+)%)#key$")) + 1] = value end,
        save = function() XML_STORE[filename] = keys note("xmlSave") end,
        delete = function() end,
    }
end
HIDDEN_XML = "profile/modSettings/FS25_FarmInventory_hidden.xml"

-- GUI elements: el{} is a plain element, txt() a text element (has setText)
local Element = {}
Element.__index = Element
function Element:setVisible(v) self.visible = v end
function Element:setSize(w, h) self.size = {w or self.size[1], h or self.size[2]} end
function Element:setTarget() end
function Element:getDescendantByName(name)
    for _, child in ipairs(self.elements) do
        if child.name == name then return child end
        local found = child:getDescendantByName(name)
        if found ~= nil then return found end
    end
    return nil
end
function Element:clone(parent)
    local copy = {}
    for k, v in pairs(self) do copy[k] = v end
    copy.size, copy.elements, copy.parent = {self.size[1], self.size[2]}, {}, parent
    setmetatable(copy, getmetatable(self))
    for _, child in ipairs(self.elements) do child:clone(copy) end
    if parent ~= nil then table.insert(parent.elements, copy) end
    return copy
end
function Element:delete()
    self.deleted = true
    if self.parent ~= nil then table.removeElement(self.parent.elements, self) end
end
function Element:invalidateLayout() note("invalidateLayout") end
function Element:updateAbsolutePosition() end
local TextElement = setmetatable({}, {__index = Element})
TextElement.__index = TextElement
function TextElement:setText(text) self.text = text end
function TextElement:getIconSize() return self.iconSize or 0 end
local function init(t, class)
    t.elements = t.elements or {}
    t.size = t.size or {0.1, 0.04}
    if t.visible == nil then t.visible = true end
    for _, child in ipairs(t.elements) do child.parent = t end
    return setmetatable(t, class)
end
function el(t) return init(t or {}, Element) end
function txt(text, t) t = t or {} t.text = text return init(t, TextElement) end

-- the game's frame class (the price list code is stripped from gameSource.zip, so this is only its shape)
function newFrameClass()
    local F = {SUB_CATEGORY = {PRICES = 1, VEHICLES = 2}}
    function F:onFrameOpen() note("game.onFrameOpen") end
    function F:onFrameClose() note("game.onFrameClose") end
    function F:update(dt) note("game.update") end
    function F:updateAcceptedFillTypes() note("game.updateAcceptedFillTypes") end
    function F:getNumberOfSections(list) note("game.getNumberOfSections") return #self.fillTypes end
    function F:getNumberOfItemsInSection(list, section) note("game.getNumberOfItemsInSection") return #self.fillTypes[section] end
    function F:getTitleForSectionHeader(list, section) note("game.getTitleForSectionHeader") return "GAME SECTION " .. section end
    function F:populateCellForItemInSection(list, section, index, cell) note("game.populateCell") return "gameResult" end
    return F
end
InGameMenuStatisticsFrame = newFrameClass()
LoadTrigger = {toggleLoading = function(trigger, ...)
    note("game.toggleLoading")
    trigger.shown, trigger.extra = trigger.source:getAllFillLevels(trigger.farmId)
    return "started", nil, 3
end}

function newList()
    return {selectedSectionIndex = 1, selectedIndex = 1,
        reloadData = function(self) note("reloadData") end,
        setSelectedItem = function(self, section, index) note("setSelectedItem") self.selectedSectionIndex, self.selectedIndex = section, index end}
end
-- a statistics frame instance as the mod sees it: tabs PRICES / VEHICLES, product list, button lists per sub-tab
function newFrame()
    local frame = setmetatable({}, {__index = InGameMenuStatisticsFrame})
    frame.playerFarm = {farmId = 1}
    frame.fillTypes = {{ft("WHEAT"), ft("BARLEY"), ft("CANOLA")},
        {ft("MILK"), ft("WATER"), ft("SILAGE"), ft("CHAFF"), ft("FLOUR"), ft("HAY")}}   -- TMR is not in the price list
    frame.productList, frame.priceList = newList(), newList()
    frame.subCategoryPaging = {state = 1, getState = function(self) return self.state end,
        setState = function(self, state) self.state = state end}
    local function tab(text)
        return txt(text, {textAutoWidth = true, textSize = 0.02, textBold = true, iconSize = 0.005, fitExtraWidth = 0.01,
            target = frame, elements = {el({name = "background"})}})
    end
    local pricesTab, vehiclesTab = tab("PRICES"), tab("VEHICLES")
    pricesTab.onClickCallback = function(target, element)
        note("game.pricesClick")
        target.subCategoryPaging:setState(1)
    end
    frame.subCategoryTabs = {pricesTab, vehiclesTab}
    frame.subCategoryBox = el({elements = {pricesTab, vehiclesTab}})
    frame.categoryHeaderText = txt("PRICES")
    frame.menuButtonInfo = {{{inputAction = InputAction.MENU_BACK}, {inputAction = InputAction.MENU_EXTRA_2, text = "STATIONS"}},
        {{inputAction = InputAction.MENU_BACK}}}
    frame.setMenuButtonInfoDirty = function() note("dirty") end
    for _, id in ipairs({"priceListSliderBox", "fluctuationsLayoutBg", "fluctuationsContainer"}) do frame[id] = el() end
    frame.priceList.visible = true
    frame.priceList.setVisible = function(self, v) self.visible = v end
    frame.noFluctuationsText = txt("No price changes", {visible = false})
    frame.noSellpointsText = txt("No selling stations", {visible = false})
    return frame
end

-- A farm with one of everything; the list order the mod must produce is:
-- Farm Silo, Milk Tank (liquid), Cow Barn (feeding robot), Bunker, Mill, Cow Barn (animals)
function standardFarm()
    placeable({name = "Cow Barn", x = 50, z = 60,
        spec_husbandry = {storage = storage({[FT.MILK] = 80})},
        spec_husbandryFeedingRobot = {feedingRobot = {
            unloadingSpots = {{fillTypes = {[FT.HAY] = true}, fillLevel = 10, capacity = 100},
                {fillType = FT.SILAGE, fillLevel = 0, capacity = 200},
                {fillLevel = 107103, capacity = 120000}},
            fillTypeToUnloadingSpot = {[FT.TMR] = 3}}}})
    placeable({name = "Mill", spec_productionPoint = {productionPoint = {
        storage = storage({[FT.WHEAT] = 200, [FT.FLOUR] = 50}), outputFillTypeIds = {[FT.FLOUR] = true}}}})
    placeable({name = "Bunker", spec_bunkerSilo = {bunkerSilo = {state = BunkerSilo.STATE_FERMENTED,
        inputFillType = FT.CHAFF, outputFillType = FT.SILAGE, fillLevel = 3000}}})
    placeable({name = "Milk Tank", spec_silo = {storages = {storage({[FT.MILK] = 500})}}})
    placeable({name = "Farm Silo", x = 10.4, z = -20.6, xml = "silo.xml",
        spec_silo = {storages = {storage({[FT.WHEAT] = 600, [FT.BARLEY] = 0.4, [FT.CANOLA] = 0}), storage({[FT.WHEAT] = 400})}}})
    placeable({name = "Neighbour Silo", farm = 2, spec_silo = {storages = {storage({[FT.WHEAT] = 9999})}}})
end
SILO_KEY = "MapUS|silo.xml|10|-21"
function names(locations)
    local out = {}
    for _, location in ipairs(locations) do out[#out + 1] = location.kind .. ":" .. location.name end
    return table.concat(out, ", ")
end
-- the fill types of every list section, e.g. "WHEAT / MILK / HAY,SILAGE,TMR"
function sections(frame)
    local out = {}
    for _, entries in ipairs(frame.fillTypes) do
        local row = {}
        for _, entry in ipairs(entries) do row[#row + 1] = entry.name end
        out[#out + 1] = table.concat(row, ",")
    end
    return table.concat(out, " / ")
end
-- opens the menu on a new frame and clicks the INVENTORY tab
function openInventory()
    fire("loadMap", "map")
    local frame = newFrame()
    frame:onFrameOpen()
    frame.sptTab.onClickCallback()
    return frame
end
'''


def new_lua(pre="", scripts=None):
    """A fresh Lua 5.1 state with the stubs, `pre` run before the mod's scripts, then the scripts."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().TR = lua.table_from(TEXTS)
    run(lua, STUBS, "=stubs")
    if pre:
        run(lua, pre, "=pre")
    for rel in (SCRIPTS if scripts is None else scripts):
        run(lua, read_script(rel), "@" + rel)
    return lua


def read_script(rel):
    src = open(os.path.join(PROJ, rel), encoding="utf-8").read()
    return CONTINUE_RE.sub("do end", src)


def run(lua, code, chunk="=test"):
    result = lua.globals().loadstring(code, chunk)
    if isinstance(result, tuple):      # nil, message
        raise SyntaxError(result[1])
    return result()


TESTS = []


def test(func):
    TESTS.append(func)
    return func


# ----------------------------------------------------------------------------------------------- loading, hooks
@test
def scripts_load_and_hooks_register():
    assert SCRIPTS == ["scripts/FarmInventory.lua", "scripts/SiloLoadFilter.lua"], SCRIPTS
    lua = new_lua(pre="GAME = {}; for k, v in pairs(InGameMenuStatisticsFrame) do GAME[k] = v end; GAME_TOGGLE = LoadTrigger.toggleLoading")
    run(lua, r'''
    eq(#LISTENERS, 2, "mod event listeners")
    ok(LISTENERS[1] == FarmInventory and LISTENERS[2] == SiloLoadFilter, "listeners are the two mod tables")
    ok(InGameMenuStatisticsFrame.sptHooksInstalled and LoadTrigger.sltHooksInstalled, "hook flags")
    for _, name in ipairs({"onFrameOpen", "onFrameClose", "update", "updateAcceptedFillTypes", "getNumberOfSections",
        "getNumberOfItemsInSection", "getTitleForSectionHeader", "populateCellForItemInSection"}) do
        ok(InGameMenuStatisticsFrame[name] ~= GAME[name], name .. " was not wrapped")
    end
    ok(LoadTrigger.toggleLoading ~= GAME_TOGGLE, "LoadTrigger.toggleLoading was not wrapped")
    ''')
    # a second load (next savegame in the same game session) must not stack the hooks again
    run(lua, "WRAPPED = InGameMenuStatisticsFrame.onFrameOpen; WRAPPED_TOGGLE = LoadTrigger.toggleLoading")
    for rel in SCRIPTS:
        run(lua, read_script(rel), "@" + rel)
    run(lua, r'''
    ok(InGameMenuStatisticsFrame.onFrameOpen == WRAPPED and LoadTrigger.toggleLoading == WRAPPED_TOGGLE, "hooks were stacked")
    ''')


@test
def unshipped_diag_script_compiles():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    result = lua.globals().loadstring(read_script("scripts/SiloPricesDiag.lua"), "@scripts/SiloPricesDiag.lua")
    assert not isinstance(result, tuple), result


@test
def missing_game_classes_disable_the_mod_without_error():
    lua = new_lua(pre="InGameMenuStatisticsFrame = nil; LoadTrigger = nil")
    run(lua, r'''
    eq(#LISTENERS, 0, "listeners without the game classes")
    ok(logHas("InGameMenuStatisticsFrame not available, tab disabled"), "no log line for the missing frame class")
    ok(logHas("LoadTrigger.toggleLoading not available, filter disabled"), "no log line for the missing LoadTrigger")
    -- the data side still works
    standardFarm()
    eq(#FarmInventory.getOwnLocations(1), 6, "locations")
    g_currentMission.placeableSystem = nil
    eq(#FarmInventory.getOwnLocations(1), 0, "locations without a placeable system")
    ''')
    lua = new_lua(pre="LoadTrigger = {}")       # class there, function gone
    run(lua, 'eq(#LISTENERS, 1, "listeners"); eq(LoadTrigger.toggleLoading, nil, "toggleLoading")')


@test
def missing_list_function_is_logged_and_the_rest_still_hooks():
    lua = new_lua(pre="InGameMenuStatisticsFrame.populateCellForItemInSection = nil; InGameMenuStatisticsFrame.onFrameOpen = nil")
    run(lua, r'''
    ok(logHas("InGameMenuStatisticsFrame.populateCellForItemInSection not found"), "missing function not logged")
    eq(InGameMenuStatisticsFrame.populateCellForItemInSection, nil, "populateCellForItemInSection")
    standardFarm()
    local frame = openInventory()        -- onFrameOpen did not exist in the "game": the appended hook still runs
    ok(frame.sptTab ~= nil and frame.sptActive, "tab not set up")
    eq(frame:getNumberOfSections(frame.productList), 6, "sections")
    ''')


@test
def hooks_only_act_between_loadMap_and_deleteMap():
    lua = new_lua()
    run(lua, r'''
    standardFarm()
    local frame = newFrame()
    frame:onFrameOpen(); frame:update(16); frame:updateAcceptedFillTypes(); frame:onFrameClose()
    eq(frame.sptTab, nil, "tab before loadMap")
    eq(frame:getNumberOfSections(frame.productList), 2, "sections before loadMap")
    eq(calls("game.onFrameOpen") + calls("game.update") + calls("game.updateAcceptedFillTypes") + calls("game.onFrameClose"), 4, "game functions run")

    fire("loadMap", "map")
    ok(InGameMenuStatisticsFrame.sptHandler == FarmInventory and LoadTrigger.sltHandler == SiloLoadFilter, "handlers after loadMap")
    eq(FarmInventory.texts.label, "INVENTORY", "tab label")
    eq(FarmInventory.texts.kinds.feedingRobot, "FEEDING ROBOT", "kind text")
    frame:onFrameOpen()
    ok(frame.sptTab ~= nil, "no tab after loadMap")

    g_inGameMenu = {pageStatistics = frame}
    fire("deleteMap")
    ok(InGameMenuStatisticsFrame.sptHandler == nil and LoadTrigger.sltHandler == nil, "handlers after deleteMap")
    eq(frame.sptTab, nil, "tab after deleteMap")
    frame:onFrameOpen()
    eq(frame.sptTab, nil, "tab set up by a stale hook")
    eq(frame:getTitleForSectionHeader(frame.productList, 1), "GAME SECTION 1", "title after deleteMap")
    ''')


# ----------------------------------------------------------------------------------------------- stored goods
@test
def is_liquid_by_category_then_by_name():
    run(new_lua(), r'''
    ok(FarmInventory.isLiquid(FT.MILK), "MILK is in the LIQUID category")
    ok(FarmInventory.isLiquid(FT.WATER), "WATER is a liquid by name")
    ok(not FarmInventory.isLiquid(FT.WHEAT), "WHEAT is not a liquid")
    ok(not FarmInventory.isLiquid(999), "an unknown fill type is not a liquid")
    g_fillTypeManager.categoryNameToFillTypes = nil       -- map without categories
    ok(FarmInventory.isLiquid(FT.MILK) and not FarmInventory.isLiquid(FT.HAY), "name fallback without categories")
    ''')


@test
def locations_come_in_list_order_with_summed_levels():
    run(new_lua(), r'''
    standardFarm()
    local locations = FarmInventory.getOwnLocations(1)
    eq(names(locations), "silo:Farm Silo, silo:Milk Tank, feedingRobot:Cow Barn, bunkerSilo:Bunker, production:Mill, animals:Cow Barn", "order")
    local silo = locations[1]
    eq(silo.levels[FT.WHEAT], 1000, "wheat over two storages")
    eq(silo.levels[FT.BARLEY], 0.4, "barley residue")
    eq(silo.levels[FT.CANOLA], nil, "an empty fill type")
    eq(silo.key, SILO_KEY, "location key (map, xml, rounded x and z)")
    eq(names(FarmInventory.getOwnLocations(2)), "silo:Neighbour Silo", "the other farm")
    eq(#FarmInventory.getOwnLocations(nil), 0, "no farm id")
    -- a placeable without a node still gets a key
    eq(FarmInventory.getPlaceableKey({configFileName = "a.xml"}), "MapUS|a.xml|0|0", "key without a root node")
    ''')


@test
def bunker_silo_fill_type_follows_its_state():
    run(new_lua(), r'''
    local bunker = {inputFillType = FT.CHAFF, outputFillType = FT.SILAGE, fillLevel = 3000}
    placeable({name = "Bunker", spec_bunkerSilo = {bunkerSilo = bunker}})
    for state, expected in pairs({[BunkerSilo.STATE_FILL] = FT.CHAFF, [BunkerSilo.STATE_CLOSED] = FT.SILAGE,
        [BunkerSilo.STATE_FERMENTED] = FT.SILAGE, [BunkerSilo.STATE_DRAIN] = FT.SILAGE}) do
        bunker.state = state
        local levels = FarmInventory.getOwnLocations(1)[1].levels
        eq(levels[expected], 3000, "level in state " .. state)
        eq(next(levels, next(levels)), nil, "only one fill type in state " .. state)
    end
    ''')


@test
def production_lists_only_its_outputs():
    run(new_lua(), r'''
    local point = {storage = storage({[FT.WHEAT] = 200, [FT.FLOUR] = 50}), outputFillTypeIds = {[FT.FLOUR] = true}}
    placeable({name = "Mill", spec_productionPoint = {productionPoint = point}})
    local levels = FarmInventory.getOwnLocations(1)[1].levels
    eq(levels[FT.FLOUR], 50, "output"); eq(levels[FT.WHEAT], nil, "input")
    point.outputFillTypeIds = nil        -- field gone after a game patch: everything shows
    levels = FarmInventory.getOwnLocations(1)[1].levels
    eq(levels[FT.FLOUR], 50, "output without the list"); eq(levels[FT.WHEAT], 200, "input without the list")
    ''')


@test
def silo_extension_counts_toward_its_silo():
    run(new_lua(), r'''
    local load, unload = {}, {}
    placeable({name = "Extension A", spec_siloExtension = {storage = {fillLevels = {[FT.WHEAT] = 50, [FT.CANOLA] = 7},
        loadingStations = {[load] = load}, unloadingStations = {[unload] = unload}}}})
    placeable({name = "Farm Silo", spec_silo = {storages = {storage({[FT.WHEAT] = 100})}, loadingStation = load, unloadingStation = unload}})
    placeable({name = "Lonely Extension", spec_siloExtension = {storage = {fillLevels = {[FT.BARLEY] = 5}}}})
    placeable({name = "Water Extension", spec_siloExtension = {storage = {fillLevels = {[FT.WATER] = 30}, loadingStations = {[{}] = true}}}})
    local locations = FarmInventory.getOwnLocations(1)
    eq(names(locations), "silo:Farm Silo, silo:Lonely Extension, silo:Water Extension", "locations (liquid one last)")
    eq(locations[1].levels[FT.WHEAT], 150, "wheat of silo and extension")
    eq(locations[1].levels[FT.CANOLA], 7, "canola only in the extension")
    eq(locations[2].levels[FT.BARLEY], 5, "unconnected extension")
    ''')


@test
def feeding_robot_rows_from_every_known_field_layout():
    run(new_lua(), r'''
    local robot = {unloadingSpots = {
        {fillTypes = {FT.CHAFF, FT.CANOLA}, fillLevel = 1, capacity = 10},         -- list: first one
        {fillTypes = {[FT.HAY] = true, [FT.SILAGE] = true}, fillLevel = 2},        -- set: lowest index
        {fillTypeIndex = FT.WATER, capacity = 30},
        {fillType = FT.MILK, fillLevel = 4, capacity = 40},
        {someNewField = true, fillLevel = 5, capacity = 50},                       -- unknown layout
        {fillLevel = 6, capacity = 60},                                            -- found through the robot's map
        {anotherNewField = 1}}}
    robot.fillTypeToUnloadingSpot = {[FT.TMR] = robot.unloadingSpots[6]}
    local rows = FarmInventory.getFeedingRobotRows({spec_husbandryFeedingRobot = {feedingRobot = robot}})
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = string.format("%d:%d/%d", row.fillTypeIndex, row.level, row.capacity) end
    eq(table.concat(out, " "), string.format("%d:1/10 %d:2/0 %d:0/30 %d:4/40 %d:6/60", FT.CHAFF, FT.SILAGE, FT.WATER, FT.MILK, FT.TMR), "rows")
    local dumps = 0
    for _, line in ipairs(LOG) do if line:find("feeding robot bin without a known fill type", 1, true) then dumps = dumps + 1 end end
    eq(dumps, 1, "unknown bins are logged once")
    ok(logHas("someNewField=boolean"), "the unknown bin's fields are in the log")

    -- FS25_PigBarnWithRobot keeps its hoppers in its own spec, which wins over the robot's bins
    rows = FarmInventory.getFeedingRobotRows({spec_husbandryFeedingRobot = {feedingRobot = robot},
        ["spec_FS25_PigBarnWithRobot.pigFeedRobot"] = {groups = {{hopper = {marker = "HAY"}, fillLevel = 5, capacity = 50}, {foodFillType = FT.TMR}, {}}}})
    eq(#rows, 2, "pig barn rows")
    eq(rows[1].fillTypeIndex, FT.HAY, "hopper marker"); eq(rows[1].level, 5, "hopper level"); eq(rows[2].fillTypeIndex, FT.TMR, "food fill type")
    -- no robot, or a robot without bins (field renamed by a patch): no rows, no error
    eq(#FarmInventory.getFeedingRobotRows({}), 0, "no robot")
    eq(#FarmInventory.getFeedingRobotRows({spec_husbandryFeedingRobot = {feedingRobot = {}}}), 0, "robot without unloadingSpots")
    ''')


@test
def own_fill_levels_total_over_all_locations():
    run(new_lua(), r'''
    standardFarm()
    local levels = FarmInventory.getOwnFillLevels(1)
    eq(levels[FT.WHEAT], 1000, "wheat (the mill's input is not counted)")
    eq(levels[FT.MILK], 580, "milk in tank and barn")
    eq(levels[FT.SILAGE], 3000, "silage"); eq(levels[FT.FLOUR], 50, "flour")
    eq(levels[FT.HAY], 10, "hay in the robot"); eq(levels[FT.TMR], 107103, "tmr in the robot")
    eq(levels[FT.CHAFF], nil, "chaff"); eq(levels[FT.CANOLA], nil, "canola")
    ''')


# ----------------------------------------------------------------------------------------------- filtered list
@test
def filter_builds_one_section_per_location():
    run(new_lua(), r'''
    standardFarm()
    local frame = newFrame()
    local full = frame.fillTypes
    eq(FarmInventory.applyFilter(frame), 8, "rows")
    -- barley (0.4 l) is under MIN_LEVEL; the robot lists every bin, TMR from the fill type manager
    eq(sections(frame), "WHEAT / MILK / HAY,SILAGE,TMR / SILAGE / FLOUR / MILK", "sections")
    eq(names(frame.sptLocations), "silo:Farm Silo, silo:Milk Tank, feedingRobot:Cow Barn, bunkerSilo:Bunker, production:Mill, animals:Cow Barn", "locations")
    ok(frame.fillTypes[2][1] == full[2][1], "rows are the game's own entries")
    ok(frame.sptFullFillTypes == full, "full list kept")
    eq(FarmInventory.applyFilter(frame), 8, "rows when applied twice")
    ok(frame.sptFullFillTypes == full, "full list kept when applied twice")

    -- goods keep the game's order; every entry shape the game might use is understood
    g_currentMission.placeableSystem.placeables = {}
    placeable({name = "Silo", spec_silo = {storages = {storage({[FT.HAY] = 1, [FT.WHEAT] = 0.5, [FT.CANOLA] = 2, [FT.MILK] = 3, [FT.FLOUR] = 4})}}})
    frame = newFrame()
    local shapes = {FT.MILK, {fillTypeIndex = FT.CANOLA}, {fillType = FT.WHEAT}, {fillType = {index = FT.HAY}}, {index = FT.BARLEY}, "junk", {}}
    frame.fillTypes = {shapes, {ft("FLOUR")}}
    eq(FarmInventory.applyFilter(frame), 5, "rows of mixed shapes")
    eq(#frame.fillTypes, 1, "sections")
    for i = 1, 4 do ok(frame.fillTypes[1][i] == shapes[i], "row " .. i .. " out of the game's order") end
    ok(frame.fillTypes[1][5] == ft("FLOUR"), "row from the game's second section")

    frame = newFrame(); frame.fillTypes = nil
    eq(FarmInventory.applyFilter(frame), 0, "no list data")
    ''')


@test
def hidden_locations_are_left_out_saved_and_loaded():
    run(new_lua(), r'''
    standardFarm()
    fire("loadMap", "map")
    eq(next(FarmInventory.hidden), nil, "hidden list without a file")
    local barnKey = FarmInventory.getOwnLocations(1)[3].key
    FarmInventory.hidden[SILO_KEY] = true
    FarmInventory.hidden[barnKey] = true       -- hides the robot and the animals of the barn
    local frame = newFrame()
    eq(FarmInventory.applyFilter(frame), 3, "rows with hidden locations")
    eq(sections(frame), "MILK / SILAGE / FLOUR", "sections")
    eq(frame.sptHiddenCount, 3, "hidden count")
    frame.sptShowHidden = true
    eq(FarmInventory.applyFilter(frame), 8, "rows with SHOW HIDDEN")

    FarmInventory.saveHidden()
    eq(table.concat(XML_STORE[HIDDEN_XML], ";"), barnKey .. ";" .. SILO_KEY, "saved keys, sorted")
    FarmInventory.hidden = nil
    FarmInventory.loadHidden()
    ok(FarmInventory.hidden[SILO_KEY] and FarmInventory.hidden[barnKey], "keys not read back")
    ok(FarmInventory.isHidden({key = SILO_KEY}) and not FarmInventory.isHidden({key = "x"}) and not FarmInventory.isHidden({}), "isHidden")
    ''')


@test
def list_data_source_serves_the_filtered_list_only_for_the_product_list():
    run(new_lua(), r'''
    standardFarm()
    local frame = openInventory()
    local list = frame.productList
    FarmInventory.hidden[SILO_KEY] = true; frame.sptShowHidden = true
    eq(frame:getNumberOfSections(list), 6, "sections")
    eq(frame:getNumberOfItemsInSection(list, 3), 3, "robot bins")
    eq(frame:getNumberOfItemsInSection(list, 7), 0, "items of a section that isn't there")
    eq(frame:getTitleForSectionHeader(list, 1), "SILO  |  Farm Silo  (HIDDEN)", "hidden silo title")
    eq(frame:getTitleForSectionHeader(list, 3), "FEEDING ROBOT  |  Cow Barn", "robot title")
    eq(frame:getTitleForSectionHeader(list, 4), "BUNKER SILO  |  Bunker", "bunker title")
    eq(frame:getTitleForSectionHeader(list, 5), "PRODUCTION  |  Mill", "production title")
    eq(frame:getTitleForSectionHeader(list, 6), "ANIMALS  |  Cow Barn", "animals title")
    eq(calls("game.getNumberOfSections") + calls("game.getNumberOfItemsInSection") + calls("game.getTitleForSectionHeader"), 0, "game functions used")

    -- another list (the stations' price list) and station mode go to the game
    eq(frame:getTitleForSectionHeader(frame.priceList, 1), "GAME SECTION 1", "other list")
    frame.sellingStationMode = true
    eq(frame:getTitleForSectionHeader(list, 1), "GAME SECTION 1", "station mode")
    frame.sellingStationMode = false
    -- so does a list the game rebuilt behind the mod's back
    table.insert(frame.fillTypes[1], ft("HAY"))
    eq(frame:getTitleForSectionHeader(list, 1), "GAME SECTION 1", "list changed by the game")
    eq(frame:getNumberOfItemsInSection(list, 1), 2, "items from the game")
    ''')


# ----------------------------------------------------------------------------------------------- list cells
@test
def cell_amount_found_by_attribute_name():
    run(new_lua(), r'''
    standardFarm()
    local frame = openInventory()
    local name, price, level = txt("Milk"), txt("1,200"), txt("-")
    local cell = el({elements = {name, price, level}})
    cell.attributes = {fillLevel = level, storage = el()}     -- "storage" exists but is no text element
    cell.getAttribute = function(self, attribute) return self.attributes[attribute] end
    eq(frame:populateCellForItemInSection(frame.productList, 2, 1, cell), "gameResult", "result of the game's function")
    eq(level.text, "500 l", "amount in the milk tank")
    eq(price.text, "1,200", "price"); eq(name.text, "Milk", "name")
    -- the same good in another location shows that location's amount
    frame:populateCellForItemInSection(frame.productList, 6, 1, cell)
    eq(level.text, "80 l", "amount in the barn")
    eq(calls("game.populateCell"), 2, "game's populate calls")
    -- other list, missing cell or a row that isn't there: only the game's function runs
    eq(frame:populateCellForItemInSection(frame.priceList, 1, 1, cell), "gameResult", "other list")
    eq(frame:populateCellForItemInSection(frame.productList, 1, 1, nil), "gameResult", "no cell")
    eq(frame:populateCellForItemInSection(frame.productList, 1, 9, cell), "gameResult", "row out of range")
    eq(level.text, "80 l", "amount untouched")
    ''')


@test
def cell_amount_found_by_scanning_the_element_tree():
    run(new_lua(), r'''
    standardFarm()
    local frame = openInventory()
    -- no attribute names (renamed by a patch): first text that is not the name and holds "-" or a digit, at any depth
    local name, label, level, price = txt("Wheat"), txt("in stock"), txt("-"), txt("950")
    local cell = el({elements = {el({name = "icon"}), el({elements = {name, label}}), el({elements = {el({elements = {level}}), price}})}})
    cell.getAttribute = function() return nil end
    frame:populateCellForItemInSection(frame.productList, 1, 1, cell)
    eq(level.text, "1,000 l", "amount"); eq(price.text, "950", "price"); eq(label.text, "in stock", "label"); eq(name.text, "Wheat", "name")
    ok(cell.sptStorageText == level, "amount element cached on the cell")
    -- the cell is reused for another row: the cached element is written even though it now holds other text
    price.text = "-"
    frame:populateCellForItemInSection(frame.productList, 5, 1, cell)
    eq(level.text, "50 l", "flour in the mill"); eq(price.text, "-", "price of the reused cell")
    -- a cell without any matching text: nothing is written, no error
    local plain = el({elements = {txt("Wheat"), txt("in stock")}})
    eq(frame:populateCellForItemInSection(frame.productList, 1, 1, plain), "gameResult", "plain cell")
    eq(plain.elements[2].text, "in stock", "plain cell text")
    ''')


@test
def feeding_robot_cell_shows_level_and_capacity_without_prices():
    run(new_lua(), r'''
    standardFarm()
    local frame = openInventory()
    local function cellFor(title)
        local cell = el({elements = {txt(title), txt("-"), txt("450"), el({elements = {txt("+3 %"), el({name = "trend"})}})}})
        return cell
    end
    local cell = cellFor("Hay")
    frame:populateCellForItemInSection(frame.productList, 3, 1, cell)
    eq(cell.elements[1].text, "Hay", "name"); eq(cell.elements[2].text, "10 / 100 l", "amount")
    eq(cell.elements[3].text, "", "price"); eq(cell.elements[4].elements[1].text, "", "nested price text")
    cell = cellFor("Silage")
    frame:populateCellForItemInSection(frame.productList, 3, 2, cell)
    eq(cell.elements[2].text, "0 / 200 l", "empty bin")
    cell = cellFor("Tmr")                    -- a feed the price list doesn't have
    frame:populateCellForItemInSection(frame.productList, 3, 3, cell)
    eq(cell.elements[2].text, "107,103 / 120,000 l", "third bin"); eq(cell.elements[1].text, "Tmr", "name of the third bin")
    ''')


# ----------------------------------------------------------------------------------------------- tab, activation
@test
def setup_adds_one_inventory_tab_next_to_prices():
    run(new_lua(), r'''
    standardFarm()
    fire("loadMap", "map")
    local frame = newFrame()
    local pricesTab = frame.subCategoryTabs[1]
    local gameClick = pricesTab.onClickCallback
    frame:onFrameOpen()
    local tab = frame.sptTab
    eq(#frame.subCategoryBox.elements, 3, "tabs in the box")
    ok(tab ~= pricesTab and tab.parent == frame.subCategoryBox and frame.subCategoryBox.elements[3] == tab, "tab is a clone in the tab box")
    eq(tab.text, "INVENTORY", "tab text"); eq(pricesTab.text, "PRICES", "PRICES tab text")
    -- icon 0.005 + text 9 * 0.02 + 0.001 + extra 0.01
    ok(math.abs(tab.size[1] - 0.196) < 1e-9, "tab width " .. tab.size[1])
    ok(math.abs(tab:getDescendantByName("background").size[1] - 0.196) < 1e-9, "background width")
    eq(pricesTab.size[1], 0.1, "PRICES tab width")
    ok(calls("invalidateLayout") >= 1, "tab box layout not invalidated")
    ok(pricesTab.getIsSelected() and not tab.getIsSelected(), "PRICES selected at first")

    frame:onFrameOpen(); frame:onFrameOpen()
    eq(#frame.subCategoryBox.elements, 3, "tabs after opening the menu again")

    tab.onClickCallback()
    ok(frame.sptActive and tab.getIsSelected() and not pricesTab.getIsSelected(), "INVENTORY selected after a click")
    ok(tab:getDescendantByName("background").getIsSelected() and not pricesTab:getDescendantByName("background").getIsSelected(), "tab backgrounds")
    frame.subCategoryPaging:setState(2)
    ok(not tab.getIsSelected() and not pricesTab.getIsSelected(), "neither selected on another sub-tab")

    -- teardown puts the PRICES tab back exactly and removes the clone
    FarmInventory.teardown(frame)
    ok(pricesTab.onClickCallback == gameClick, "PRICES click handler not restored")
    eq(rawget(pricesTab, "getIsSelected"), nil, "PRICES getIsSelected")
    eq(rawget(pricesTab:getDescendantByName("background"), "getIsSelected"), nil, "PRICES background getIsSelected")
    ok(tab.deleted and frame.sptTab == nil and #frame.subCategoryBox.elements == 2, "clone not deleted")

    -- a frame without the expected fields (changed by a patch) is left alone
    for _, field in ipairs({"subCategoryTabs", "subCategoryPaging"}) do
        local other = newFrame(); other[field] = nil
        other:onFrameOpen()
        eq(other.sptTab, nil, "tab without " .. field)
    end
    local other = newFrame(); other.subCategoryTabs = {}
    other:onFrameOpen()
    eq(other.sptTab, nil, "tab without a PRICES tab")
    ''')


@test
def activate_swaps_the_list_and_prices_click_restores_it():
    run(new_lua(), r'''
    standardFarm()
    fire("loadMap", "map")
    local frame = newFrame()
    local full, list = frame.fillTypes, frame.productList
    frame:onFrameOpen()
    list.selectedSectionIndex, list.selectedIndex = 2, 1          -- MILK
    frame.sptTab.onClickCallback()
    eq(calls("game.pricesClick"), 1, "the game's PRICES handler ran")
    eq(sections(frame), "WHEAT / MILK / HAY,SILAGE,TMR / SILAGE / FLOUR / MILK", "sections")
    eq(frame.categoryHeaderText.text, "INVENTORY", "header")
    eq(calls("reloadData"), 1, "list reloads")
    eq(list.selectedSectionIndex .. "." .. list.selectedIndex, "2.1", "MILK still selected (first place it is kept)")
    ok(frame.priceList.visible and not frame.noSellpointsText.visible, "empty state shown with goods in stock")

    list.selectedSectionIndex, list.selectedIndex = 5, 1          -- FLOUR in the mill
    frame.subCategoryTabs[1].onClickCallback(frame, frame.subCategoryTabs[1])
    ok(not frame.sptActive and frame.fillTypes == full, "full list not restored")
    eq(frame.sptFilteredFillTypes, nil, "filter state"); eq(frame.sptLocations, nil, "locations state")
    eq(calls("game.pricesClick"), 2, "the game's PRICES handler ran again")
    eq(frame.categoryHeaderText.text, "PRICES", "header restored")
    eq(list.selectedSectionIndex .. "." .. list.selectedIndex, "2.5", "FLOUR selected in the full list")
    eq(frame:getNumberOfSections(list), 2, "sections of the full list")

    -- leaving station mode first
    frame.sellingStationMode = true
    frame.onButtonChangeSellingStationMode = function(self) self.sellingStationMode = false note("leftStationMode") end
    frame.sptTab.onClickCallback()
    eq(calls("leftStationMode"), 1, "station mode left"); eq(#frame.fillTypes, 6, "sections after station mode")
    ''')


@test
def empty_farm_shows_the_no_goods_text_and_restores_the_page():
    run(new_lua(), r'''
    placeable({name = "Empty Silo", spec_silo = {storages = {storage({[FT.WHEAT] = 0.2})}}})
    local frame = openInventory()
    eq(#frame.fillTypes, 0, "sections")
    eq(frame:getNumberOfSections(frame.productList), 0, "sections served")
    for _, id in ipairs(FarmInventory.EMPTY_STATE_HIDDEN) do
        ok(frame[id] ~= nil and frame[id].visible == false, id .. " still visible")
    end
    eq(frame.noSellpointsText.text, TR.ui_sptNoGoods, "no goods text"); eq(frame.noSellpointsText.visible, true, "no goods text visible")

    frame.subCategoryTabs[1].onClickCallback(frame, frame.subCategoryTabs[1])
    ok(frame.priceList.visible and frame.priceListSliderBox.visible and frame.fluctuationsContainer.visible, "page elements not shown again")
    eq(frame.noFluctuationsText.visible, false, "an element that was hidden before")
    eq(frame.noSellpointsText.text, "No selling stations", "the game's text"); eq(frame.noSellpointsText.visible, false, "the game's text visibility")

    -- a frame that lost some of these elements in a patch
    local bare = newFrame()
    for _, id in ipairs({"priceList", "noSellpointsText", "fluctuationsLayoutBg", "categoryHeaderText"}) do bare[id] = nil end
    bare:onFrameOpen(); bare.sptTab.onClickCallback()
    ok(bare.sptEmptyShown, "empty state on the bare frame")
    bare:onFrameClose()
    ok(not bare.sptEmptyShown and not bare.sptActive, "bare frame closed")
    ''')


@test
def closing_the_menu_restores_silently_and_reloads_on_next_open():
    run(new_lua(), r'''
    standardFarm()
    local frame = openInventory()
    local list = frame.productList
    FarmInventory.updateButtons(frame)
    list.selectedSectionIndex, list.selectedIndex = 4, 1          -- SILAGE in the bunker
    local reloads, selects, dirty = calls("reloadData"), calls("setSelectedItem"), calls("dirty")
    frame:onFrameClose()
    eq(calls("game.onFrameClose"), 1, "the game's close")
    ok(not frame.sptActive and #frame.fillTypes == 2, "full list not restored")
    eq(calls("reloadData"), reloads, "list reloads while closing")
    eq(calls("setSelectedItem"), selects, "selection events while closing")
    eq(calls("dirty"), dirty, "button bar updates while closing")
    eq(#frame.menuButtonInfo[1], 2, "buttons of the PRICES sub-tab")
    eq(list.selectedSectionIndex .. "." .. list.selectedIndex, "2.3", "SILAGE selected in the full list")
    frame:onFrameClose()                                           -- closing twice is harmless

    frame:onFrameOpen()
    eq(calls("reloadData"), reloads + 1, "list reloaded on the next open")
    eq(frame.sptReloadOnOpen, nil, "reload flag")
    eq(#frame.subCategoryBox.elements, 3, "tabs")
    frame:onFrameOpen()
    eq(calls("reloadData"), reloads + 1, "list reloaded only once")
    ''')


@test
def update_follows_tab_changes_and_lists_rebuilt_by_the_game():
    run(new_lua(), r'''
    standardFarm()
    local frame = openInventory()
    frame:update(16)
    eq(calls("reloadData"), 1, "no reload while nothing changed")

    -- the game rebuilds its list while the tab is open
    local rebuilt = {{ft("WHEAT")}, {ft("MILK"), ft("FLOUR")}}
    frame.fillTypes = rebuilt
    frame.categoryHeaderText.text = "PRICES"
    frame:update(16)
    eq(sections(frame), "WHEAT / MILK / HAY,SILAGE,TMR / FLOUR / MILK", "sections after the rebuild")
    ok(frame.sptFullFillTypes == rebuilt, "the rebuilt list is the full list now")
    eq(frame.categoryHeaderText.text, "INVENTORY", "header put back")
    eq(calls("reloadData"), 2, "reload after the rebuild")

    -- another sub-tab (keyboard paging): the tab switches itself off
    frame.subCategoryPaging:setState(2)
    frame.categoryHeaderText.text = "VEHICLES"
    frame:update(16)
    ok(not frame.sptActive and frame.fillTypes == rebuilt, "not switched off on another sub-tab")
    eq(frame.categoryHeaderText.text, "VEHICLES", "the other sub-tab's header")
    frame:update(16)
    eq(calls("game.update"), 4, "the game's update")
    ''')


@test
def station_mode_accepted_goods_are_limited_to_stock():
    run(new_lua(), r'''
    standardFarm()
    fire("loadMap", "map")
    local frame = newFrame()
    local unknown = {title = "?"}
    frame.currentAcceptedFillTypes = {ft("WHEAT"), ft("CANOLA"), ft("FLOUR"), unknown, ft("CHAFF")}
    frame:updateAcceptedFillTypes()
    eq(#frame.currentAcceptedFillTypes, 5, "accepted goods while the tab is off")
    frame:onFrameOpen(); frame.sptTab.onClickCallback()
    local reloads = calls("reloadData")
    frame:updateAcceptedFillTypes()
    local accepted = frame.currentAcceptedFillTypes
    ok(#accepted == 3 and accepted[1] == ft("WHEAT") and accepted[2] == ft("FLOUR") and accepted[3] == unknown, "accepted goods in stock")
    eq(calls("reloadData"), reloads + 1, "price list reload")
    frame.currentAcceptedFillTypes = nil
    frame:updateAcceptedFillTypes()                                -- no station selected: no error
    ''')


# ----------------------------------------------------------------------------------------------- buttons
@test
def buttons_take_free_menu_actions_and_hide_or_show_locations():
    run(new_lua(), r'''
    standardFarm()
    local frame = openInventory()
    local infos, list = frame.menuButtonInfo[1], frame.productList
    local function button(text)
        for _, info in ipairs(infos) do if info.sptOwner == FarmInventory and info.text == text then return info end end
        return nil
    end
    frame:update(16)
    eq(#infos, 3, "buttons (MENU_BACK, the game's, HIDE)")
    local hide = button("HIDE")
    ok(hide ~= nil, "no HIDE button")
    eq(hide.inputAction, "MENU_EXTRA_3", "HIDE action (MENU_EXTRA_2 is taken by the game)")
    eq(#frame.menuButtonInfo[2], 1, "buttons of the other sub-tab")
    local dirty = calls("dirty")
    frame:update(16); frame:update(16)
    ok(button("HIDE") == hide and #infos == 3 and calls("dirty") == dirty, "buttons rebuilt although nothing changed")

    -- HIDE on the selected section (Farm Silo)
    hide.callback()
    eq(sections(frame), "MILK / HAY,SILAGE,TMR / SILAGE / FLOUR / MILK", "sections without the silo")
    eq(table.concat(XML_STORE[HIDDEN_XML], ";"), SILO_KEY, "saved hidden list")
    ok(calls("createFolder") == 1 and calls("xmlSave") == 1, "hidden list saved once")
    eq(#infos, 4, "buttons after hiding")
    eq(button("HIDE").inputAction, "MENU_EXTRA_3", "HIDE action")
    eq(button("SHOW HIDDEN (1)").inputAction, "MENU_EXTRA_4", "SHOW HIDDEN action")

    button("SHOW HIDDEN (1)").callback()
    eq(#frame.fillTypes, 6, "sections with hidden ones shown")
    ok(button("HIDE HIDDEN (1)") ~= nil and button("SHOW HIDDEN (1)") == nil, "SHOW HIDDEN did not turn into HIDE HIDDEN")
    list.selectedSectionIndex, list.selectedIndex = 1, 1
    frame:update(16)
    ok(button("UNHIDE") ~= nil and button("HIDE") == nil, "no UNHIDE on the hidden silo")
    button("UNHIDE").callback()
    eq(#XML_STORE[HIDDEN_XML], 0, "saved hidden list after UNHIDE")
    ok(button("HIDE") ~= nil and button("HIDE HIDDEN (1)") == nil and #infos == 3, "buttons after UNHIDE")

    -- the game replaces the button list: the button is added to the new one
    infos = {{inputAction = InputAction.MENU_BACK}}
    frame.menuButtonInfo[1] = infos
    frame:update(16)
    eq(button("HIDE").inputAction, "MENU_EXTRA_2", "HIDE in the new list, first free action")

    -- station mode and leaving the tab take them out again
    frame.sellingStationMode = true
    frame:update(16)
    eq(#infos, 1, "buttons in station mode")
    frame.sellingStationMode = false
    frame:update(16)
    eq(#infos, 2, "buttons back after station mode")
    dirty = calls("dirty")
    frame.subCategoryTabs[1].onClickCallback(frame, frame.subCategoryTabs[1])
    ok(#infos == 1 and frame.sptButtons == nil and calls("dirty") == dirty + 1, "buttons not removed with the tab")
    ''')


@test
def buttons_cope_with_no_free_action_and_a_missing_button_list():
    run(new_lua(), r'''
    standardFarm()
    local frame = openInventory()
    FarmInventory.hidden[SILO_KEY] = true
    FarmInventory.refresh(frame)
    local infos = frame.menuButtonInfo[1]
    table.insert(infos, {inputAction = InputAction.MENU_EXTRA_3})
    InputAction.MENU_EXTRA_4 = nil                 -- action removed by a patch: only what fits is added
    frame:update(16)
    eq(#infos, 3, "buttons when no action is free")
    infos[3] = nil
    frame.sptButtons = nil
    frame:update(16)
    ok(#infos == 3 and infos[3].text == "HIDE" and infos[3].inputAction == "MENU_EXTRA_3", "one free action goes to HIDE")

    frame.menuButtonInfo = nil                     -- field renamed by a patch
    frame:update(16)
    eq(frame.sptButtons, nil, "button state without a button list")
    FarmInventory.toggleShowHidden(frame)
    eq(#frame.fillTypes, 6, "SHOW HIDDEN still works without a button list")
    ''')


# ----------------------------------------------------------------------------------------------- silo load filter
@test
def load_filter_shows_only_goods_in_stock():
    run(new_lua(), r'''
    fire("loadMap", "map")
    local Source = {}
    Source.__index = Source
    function Source:getAllFillLevels(farmId) return self.levels, "capacity " .. tostring(farmId) end
    local source = setmetatable({levels = {[FT.WHEAT] = 1200, [FT.BARLEY] = 0.4, [FT.CANOLA] = 0, [FT.MILK] = 0.5}}, Source)
    local trigger = {source = source, farmId = 1}
    local a, b, c = LoadTrigger.toggleLoading(trigger)
    ok(a == "started" and b == nil and c == 3, "the game's results are passed on")
    eq(trigger.shown[FT.WHEAT], 1200, "wheat"); eq(trigger.shown[FT.MILK], 0.5, "milk at the minimum")
    eq(trigger.shown[FT.BARLEY], nil, "barley residue"); eq(trigger.shown[FT.CANOLA], nil, "empty canola")
    eq(trigger.extra, "capacity 1", "second result of getAllFillLevels")
    eq(source.levels[FT.BARLEY], 0.4, "the storage's own table")
    eq(rawget(source, "getAllFillLevels"), nil, "the swapped function was not taken out again")
    ok(source.getAllFillLevels == Source.getAllFillLevels and #SiloLoadFilter.swaps == 0, "source not back to its class function")

    -- nothing in stock: the game's own list
    source.levels = {[FT.WHEAT] = 0, [FT.BARLEY] = 0.2}
    LoadTrigger.toggleLoading(trigger)
    ok(trigger.shown == source.levels, "full list when nothing is in stock")
    -- a source with its own function gets exactly that one back
    local own = function(self) return {[FT.HAY] = 5, [FT.TMR] = 0} end
    source.getAllFillLevels = own
    LoadTrigger.toggleLoading(trigger)
    ok(trigger.shown[FT.HAY] == 5 and trigger.shown[FT.TMR] == nil and rawget(source, "getAllFillLevels") == own, "own function")
    -- something that is not a table goes through untouched
    source.getAllFillLevels = function() return nil end
    LoadTrigger.toggleLoading(trigger)
    eq(trigger.shown, nil, "nil fill levels")
    ''')


@test
def load_filter_stands_back_and_cleans_up_after_errors():
    run(new_lua(), r'''
    fire("loadMap", "map")
    local levels = {[FT.WHEAT] = 5, [FT.CANOLA] = 0}
    local function newSource() return {getAllFillLevels = function() return levels end} end
    -- cases where the list must stay the game's
    for what, trigger in pairs({
        ["while loading"] = {source = newSource(), isLoading = true},
        ["infinite trigger"] = {source = newSource(), hasInfiniteCapacity = true},
        ["infinite source"] = {source = setmetatable({hasInfiniteCapacity = true}, {__index = newSource()})}}) do
        LoadTrigger.toggleLoading(trigger)
        ok(trigger.shown == levels, "list filtered " .. what)
    end
    -- the game's function stops with an error: the swap is undone on the next frame
    local source = newSource()
    local own = source.getAllFillLevels
    local failed = not pcall(SiloLoadFilter.toggleLoading, {source = source}, function() error("game error") end)
    ok(failed and source.getAllFillLevels ~= own and #SiloLoadFilter.swaps == 1, "swap expected to be left after the error")
    fire("update", 16)
    ok(source.getAllFillLevels == own and #SiloLoadFilter.swaps == 0, "swap not undone by update")
    -- no handler (savegame without the mod): the game's function, unfiltered
    fire("deleteMap")
    local trigger = {source = newSource()}
    LoadTrigger.toggleLoading(trigger)
    ok(trigger.shown == levels, "list filtered after deleteMap")
    ''')


# ----------------------------------------------------------------------------------------------- runner
def main():
    failed = 0
    for func in TESTS:
        try:
            func()
            print(f"PASS  {func.__name__}")
        except Exception as ex:      # a Lua error, a failed check or a Python assert
            failed += 1
            message = str(ex).strip() or type(ex).__name__
            print(f"FAIL  {func.__name__}: {message.splitlines()[0]}")
    print(f"{len(TESTS) - failed} of {len(TESTS)} tests passed" + ("" if failed == 0 else f", {failed} FAILED"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
