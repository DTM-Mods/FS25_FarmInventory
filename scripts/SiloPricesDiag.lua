-- Temporary diagnostic: dumps the structure of the in-game menu statistics frame
-- (PRICES / VEHICLES / ... tabs) to log.txt so the real tab can be built against it.
-- All lines are prefixed with [SPT-DIAG].

SiloPricesDiag = {}
SiloPricesDiag.TAG = "[SPT-DIAG]"
SiloPricesDiag.MAX_TRACE_LINES = 400
SiloPricesDiag.traceLines = 0
SiloPricesDiag.traceSeen = {}
SiloPricesDiag.dumped = false
SiloPricesDiag.openTime = nil

local function log(fmt, ...)
    print(SiloPricesDiag.TAG .. " " .. string.format(fmt, ...))
end

local classNames = nil
local function getClassName(obj)
    if type(obj) ~= "table" then
        return type(obj)
    end
    if classNames == nil then
        classNames = {}
        for k, v in pairs(_G) do
            if type(k) == "string" and type(v) == "table" and (k:find("Element$") or k:find("Frame$") or k:find("Graph")) then
                classNames[v] = k
            end
        end
    end
    local mt = getmetatable(obj)
    local guard = 0
    while mt ~= nil and guard < 10 do
        local idx = rawget(mt, "__index")
        if idx ~= nil and classNames[idx] ~= nil then
            return classNames[idx]
        end
        if type(idx) ~= "table" then
            break
        end
        mt = getmetatable(idx)
        guard = guard + 1
    end
    return "?"
end

local function isElement(v)
    return type(v) == "table" and rawget(v, "elements") ~= nil and rawget(v, "profile") ~= nil
end

local function describeElement(e)
    local text = ""
    if e.text ~= nil and e.text ~= "" then
        text = " text='" .. tostring(e.text) .. "'"
    end
    local extra = ""
    if e.dataSource ~= nil or e.delegate ~= nil then
        extra = string.format(" [list: dataSource=%s delegate=%s startClipping=%s]", getClassName(e.dataSource), getClassName(e.delegate), tostring(e.startClipperElementName))
    end
    return string.format("%s id=%s name=%s profile=%s visible=%s children=%d%s%s",
        getClassName(e), tostring(e.id), tostring(e.name), tostring(e.profile), tostring(e.visible),
        e.elements ~= nil and #e.elements or 0, text, extra)
end

local function describeValue(v)
    local t = type(v)
    if t == "table" then
        if isElement(v) then
            return "ELEMENT " .. describeElement(v)
        end
        local n = 0
        for _ in pairs(v) do
            n = n + 1
        end
        return string.format("table(%s, size=%d, #=%d)", getClassName(v), n, #v)
    elseif t == "string" then
        return "'" .. v .. "'"
    end
    return tostring(v)
end

local function dumpTree(e, depth, maxDepth, state)
    if state.count > 600 then
        return
    end
    state.count = state.count + 1
    log("%s%s", string.rep("  ", depth), describeElement(e))
    if depth >= maxDepth or e.elements == nil then
        return
    end
    local isList = e.dataSource ~= nil
    for i, child in ipairs(e.elements) do
        if isList and i > 2 then
            log("%s  ... (%d more list cells)", string.rep("  ", depth), #e.elements - 2)
            break
        end
        dumpTree(child, depth + 1, maxDepth, state)
    end
end

local function dumpData(name, v, depth, maxDepth, visited)
    if type(v) ~= "table" or isElement(v) or visited[v] then
        return
    end
    visited[v] = true
    local count = 0
    for k, sub in pairs(v) do
        count = count + 1
        if count > 12 then
            log("%s  ...", string.rep("  ", depth))
            break
        end
        log("%s%s.%s = %s", string.rep("  ", depth), name, tostring(k), describeValue(sub))
        if depth < maxDepth and type(sub) == "table" and type(sub) ~= "function" then
            dumpData(tostring(k), sub, depth + 1, maxDepth, visited)
        end
    end
end

function SiloPricesDiag.dumpClass()
    local f = InGameMenuStatisticsFrame
    if f == nil then
        log("InGameMenuStatisticsFrame is nil")
        return
    end
    local names = {}
    for k, v in pairs(f) do
        table.insert(names, string.format("%s:%s", tostring(k), type(v)))
    end
    table.sort(names)
    log("CLASS InGameMenuStatisticsFrame members (%d):", #names)
    for _, n in ipairs(names) do
        log("  %s", n)
    end
    for k, v in pairs(f) do
        if type(v) == "table" then
            log("CLASS TABLE %s:", tostring(k))
            dumpData(tostring(k), v, 1, 1, {})
        end
    end
end

function SiloPricesDiag.dumpInstance(frame)
    log("===== INSTANCE DUMP (subCategory state=%s) =====", tostring(frame.subCategoryPaging ~= nil and frame.subCategoryPaging:getState()))

    local keys = {}
    for k in pairs(frame) do
        table.insert(keys, tostring(k))
    end
    table.sort(keys)
    log("INSTANCE fields (%d):", #keys)
    for _, k in ipairs(keys) do
        log("  %s = %s", k, describeValue(frame[k]))
    end

    if frame.subCategoryTabs ~= nil then
        for i, tab in pairs(frame.subCategoryTabs) do
            log("TAB %s: %s", tostring(i), describeElement(tab))
        end
    end
    if frame.subCategoryPaging ~= nil then
        log("PAGING texts=%s state=%s", table.concat(frame.subCategoryPaging.texts or {}, ","), tostring(frame.subCategoryPaging:getState()))
    end

    if frame.subCategoryPages ~= nil then
        for i, page in pairs(frame.subCategoryPages) do
            log("----- PAGE %s tree -----", tostring(i))
            local maxDepth = (i == 1) and 9 or 2
            dumpTree(page, 0, maxDepth, {count = 0})
        end
    end

    log("----- non-element data tables on instance -----")
    for _, k in ipairs(keys) do
        local v = frame[k]
        if type(v) == "table" and not isElement(v) and k ~= "subCategoryPages" and k ~= "subCategoryTabs" and k ~= "elements" and k ~= "parent" and k ~= "target" then
            log("DATA %s = %s", k, describeValue(v))
            dumpData(k, v, 1, 2, {})
        end
    end
    log("===== END INSTANCE DUMP =====")
end

local SKIP_TRACE = {
    update = true, draw = true, mouseEvent = true, keyEvent = true, inputEvent = true,
    getIsVisible = true, new = true, getMenuButtonInfo = true
}

local function argSummary(...)
    local parts = {}
    local n = select("#", ...)
    for i = 1, math.min(n, 5) do
        local a = select(i, ...)
        if isElement(a) then
            table.insert(parts, "elem:" .. tostring(a.id or a.name or a.profile))
        elseif type(a) == "table" then
            table.insert(parts, "table:" .. getClassName(a))
        else
            table.insert(parts, tostring(a))
        end
    end
    return table.concat(parts, ", ")
end

function SiloPricesDiag.installTrace()
    local f = InGameMenuStatisticsFrame
    for name, fn in pairs(f) do
        if type(fn) == "function" and not SKIP_TRACE[name] then
            f[name] = function(self, ...)
                if SiloPricesDiag.openTime ~= nil and SiloPricesDiag.traceLines < SiloPricesDiag.MAX_TRACE_LINES then
                    local key = name .. "|" .. argSummary(...)
                    local seen = SiloPricesDiag.traceSeen[key] or 0
                    if seen < 3 then
                        SiloPricesDiag.traceSeen[key] = seen + 1
                        SiloPricesDiag.traceLines = SiloPricesDiag.traceLines + 1
                        log("CALL %s(%s)", name, argSummary(...))
                    end
                end
                local r = {fn(self, ...)}
                if name == "getNumberOfItemsInSection" and SiloPricesDiag.openTime ~= nil and SiloPricesDiag.traceLines < SiloPricesDiag.MAX_TRACE_LINES then
                    local list = ...
                    local key = "ret|" .. tostring(list and list.id) .. "|" .. tostring(r[1])
                    if SiloPricesDiag.traceSeen[key] == nil then
                        SiloPricesDiag.traceSeen[key] = 1
                        log("  -> getNumberOfItemsInSection(%s) returned %s", tostring(list and list.id), tostring(r[1]))
                    end
                end
                return unpack(r)
            end
        end
    end
end

function SiloPricesDiag:loadMap()
    log("loadMap: game version %s", tostring(g_gameVersionDisplay))
    SiloPricesDiag.dumpClass()

    if InGameMenuStatisticsFrame ~= nil then
        InGameMenuStatisticsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuStatisticsFrame.onFrameOpen, function(frame)
            if SiloPricesDiag.openTime == nil then
                SiloPricesDiag.openTime = g_time
                log("onFrameOpen (first time)")
            end
        end)
        InGameMenuStatisticsFrame.update = Utils.appendedFunction(InGameMenuStatisticsFrame.update, function(frame, dt)
            if SiloPricesDiag.openTime ~= nil and not SiloPricesDiag.dumped and g_time - SiloPricesDiag.openTime > 1500 then
                SiloPricesDiag.dumped = true
                SiloPricesDiag.dumpInstance(frame)
            end
            local state = frame.subCategoryPaging ~= nil and frame.subCategoryPaging:getState() or nil
            if state ~= SiloPricesDiag.lastState then
                log("subCategory state %s -> %s", tostring(SiloPricesDiag.lastState), tostring(state))
                SiloPricesDiag.lastState = state
            end
        end)
    end

    -- storages owned by the player (to verify silo detection)
    local farmId = g_currentMission:getFarmId()
    log("player farmId=%s", tostring(farmId))
    for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
        local isSilo = placeable.spec_silo ~= nil
        local isExt = placeable.spec_siloExtension ~= nil
        if (isSilo or isExt) then
            local levels = {}
            local storages = isSilo and placeable.spec_silo.storages or {placeable.spec_siloExtension.storage}
            for _, storage in ipairs(storages or {}) do
                for fillTypeIndex, level in pairs(storage.fillLevels or {}) do
                    if level > 0 then
                        table.insert(levels, string.format("%s=%.0f", tostring(g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)), level))
                    end
                end
            end
            log("SILO %s owner=%s silo=%s ext=%s husbandry=%s production=%s levels: %s", tostring(placeable:getName()), tostring(placeable:getOwnerFarmId()),
                tostring(isSilo), tostring(isExt), tostring(placeable.spec_husbandry ~= nil), tostring(placeable.spec_productionPoint ~= nil), table.concat(levels, " "))
        end
    end
end

if InGameMenuStatisticsFrame ~= nil then
    SiloPricesDiag.installTrace()
else
    log("InGameMenuStatisticsFrame not available at source time")
end

addModEventListener(SiloPricesDiag)
