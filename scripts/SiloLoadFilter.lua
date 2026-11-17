-- Silo Load Filter
-- When filling at a silo (R at a load trigger), the fill type list only shows goods that are
-- actually in stock, so empty entries don't have to be scrolled past.
--
-- LoadTrigger:toggleLoading builds that list from source:getAllFillLevels(farmId). While it
-- runs, the source's getAllFillLevels is swapped for a version that drops empty entries.

SiloLoadFilter = {}
SiloLoadFilter.TAG = "[SiloLoadFilter]"
SiloLoadFilter.MIN_LEVEL = 0.5 -- liters; smaller residues show as "0 l" in the list
SiloLoadFilter.swaps = {}      -- {source, ownField} of every swap in place (only while toggleLoading runs)

-- Returns only the entries with stock, or the full table when nothing is in stock (so the
-- game's own empty-silo behaviour is unchanged)
local function filterFillLevels(fillLevels)
    if type(fillLevels) ~= "table" then
        return fillLevels
    end
    local filtered, count = {}, 0
    for fillTypeIndex, level in pairs(fillLevels) do
        if type(level) == "number" and level >= SiloLoadFilter.MIN_LEVEL then
            filtered[fillTypeIndex] = level
            count = count + 1
        end
    end
    if count == 0 then
        return fillLevels
    end
    return filtered
end

local function filterFirst(fillLevels, ...)
    return filterFillLevels(fillLevels), ...
end

function SiloLoadFilter.toggleLoading(trigger, superFunc, ...)
    local source = trigger.source
    if trigger.isLoading or trigger.hasInfiniteCapacity or type(source) ~= "table"
        or source.hasInfiniteCapacity or source.getAllFillLevels == nil then
        return superFunc(trigger, ...)
    end

    local ownField = rawget(source, "getAllFillLevels")
    local getAllFillLevels = source.getAllFillLevels
    local swap = {source = source, ownField = ownField}
    table.insert(SiloLoadFilter.swaps, swap)
    source.getAllFillLevels = function(self, ...)
        return filterFirst(getAllFillLevels(self, ...))
    end
    local results = {superFunc(trigger, ...)}
    source.getAllFillLevels = ownField
    table.removeElement(SiloLoadFilter.swaps, swap)

    return unpack(results, 1, table.maxn(results))
end

-- Every frame: a swap still in place means toggleLoading stopped with an error (shown in the log),
-- so the source gets its own getAllFillLevels back. Newest first, in case calls were nested.
function SiloLoadFilter.restoreLeftovers()
    local swaps = SiloLoadFilter.swaps
    for i = #swaps, 1, -1 do
        swaps[i].source.getAllFillLevels = swaps[i].ownField
        swaps[i] = nil
    end
end

---------------------------------------------------------------------------------------------
-- Hook (dispatches through LoadTrigger.sltHandler so a hook installed by an earlier session
-- never runs stale code, and does nothing in savegames without this mod)
---------------------------------------------------------------------------------------------

local function installHooks()
    if LoadTrigger.sltHooksInstalled then
        return
    end
    LoadTrigger.sltHooksInstalled = true
    LoadTrigger.toggleLoading = Utils.overwrittenFunction(LoadTrigger.toggleLoading, function(trigger, superFunc, ...)
        local handler = LoadTrigger.sltHandler
        if handler ~= nil then
            return handler.toggleLoading(trigger, superFunc, ...)
        end
        return superFunc(trigger, ...)
    end)
    print(SiloLoadFilter.TAG .. " LoadTrigger.toggleLoading hooked, empty fill types hidden")
end

function SiloLoadFilter:loadMap()
    LoadTrigger.sltHandler = SiloLoadFilter
end

function SiloLoadFilter:update(dt)
    if #SiloLoadFilter.swaps > 0 then
        SiloLoadFilter.restoreLeftovers()
    end
end

function SiloLoadFilter:deleteMap()
    SiloLoadFilter.restoreLeftovers()
    LoadTrigger.sltHandler = nil
end

if LoadTrigger ~= nil and LoadTrigger.toggleLoading ~= nil then
    installHooks()
    addModEventListener(SiloLoadFilter)
else
    print(SiloLoadFilter.TAG .. " LoadTrigger.toggleLoading not available, filter disabled")
end
