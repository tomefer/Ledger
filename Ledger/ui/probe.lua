-- Ledger - ui/probe.lua
-- Gathers the raw data for /ldg probe: a snapshot of which APIs this
-- client build actually exposes, to diagnose compatibility with an
-- unfamiliar client (this port to WoW Forever, interface 16001,
-- included) without assuming anything. Every call here is guarded --
-- a global that doesn't exist, or one that exists but errors when
-- called, is reported as such instead of breaking the addon. Thin
-- layer: formatting the gathered data into text lives in
-- core/probe.lua, this file only reads WoW APIs.

local ADDON_NAME, Ledger = ...

-- Which of the probed functions take "player" as their only argument.
-- false/omitted means called with no arguments at all -- none of the
-- functions this probes need more than that.
local PROBE_API_TAKES_PLAYER = {
    UnitXP            = true,
    UnitXPMax         = true,
    GetXPExhaustion   = false,
    RequestTimePlayed = false,
    UnitOnTaxi        = true,
    GetUnitSpeed      = true,
}

-- Fixed order (never derived from pairs(), which has no stable order
-- in Lua), so /ldg probe's output is deterministic run to run.
local PROBE_API_ORDER = {
    "UnitXP", "UnitXPMax", "GetXPExhaustion", "RequestTimePlayed", "UnitOnTaxi", "GetUnitSpeed",
}

-- Calls the global function `name` (if it exists) and captures up to
-- 4 return values, trimming trailing nils from the end so "returned
-- nothing" (e.g. RequestTimePlayed) reports an empty list instead of
-- a wall of "nil"s. Never lets a missing or erroring API propagate:
-- that's the whole point of this probe.
local function ProbeCall(name)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return { name = name, present = false }
    end

    local ok, a, b, c, d
    if PROBE_API_TAKES_PLAYER[name] then
        ok, a, b, c, d = pcall(fn, "player")
    else
        ok, a, b, c, d = pcall(fn)
    end

    if not ok then
        return { name = name, present = true, callFailed = true, error = a }
    end

    local values = { a, b, c, d }
    for i = 4, 1, -1 do
        if values[i] == nil then
            table.remove(values, i)
        else
            break
        end
    end

    return { name = name, present = true, values = values }
end

local function GatherBuildInfo()
    if type(GetBuildInfo) ~= "function" then
        return { present = false }
    end

    local ok, version, build, date, tocversion = pcall(GetBuildInfo)
    if not ok then
        return { present = true, callFailed = true, error = version }
    end

    return { present = true, version = version, build = build, date = date, tocversion = tocversion }
end

-- Every global whose name starts with "COMBATLOG_XPGAIN_" -- both
-- families (the base kill/explore variants and the EXHAUSTION/rested
-- ones, see core/chat_patterns.lua), sorted for deterministic output.
local function GatherXPGainGlobals()
    local names = {}
    for key, value in pairs(_G) do
        if type(value) == "string" and key:find("^COMBATLOG_XPGAIN_") then
            names[#names + 1] = key
        end
    end
    table.sort(names)
    return names
end

function Ledger.GatherProbeData()
    local apis = {}
    for _, name in ipairs(PROBE_API_ORDER) do
        apis[#apis + 1] = ProbeCall(name)
    end

    return {
        build           = GatherBuildInfo(),
        apis            = apis,
        xpGainGlobals   = GatherXPGainGlobals(),
        chatInfoPresent = C_ChatInfo ~= nil,
        -- Set by ui/xp_bar.lua: AnchorToNativeBar on every redraw; nil
        -- if the xp bar has never been redrawn yet this session (e.g.
        -- /ldg bar was never turned on).
        xpBarAnchor     = Ledger.xpBarAnchorInfo,
    }
end
