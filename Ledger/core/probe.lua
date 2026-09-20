-- Ledger - core/probe.lua
-- Text formatter for /ldg probe, the compatibility diagnostic: does
-- this client build actually expose the APIs Ledger depends on (or
-- might want to depend on), and with what values. Pure logic: does
-- not use any WoW API, reads the table it's given (gathered by
-- ui/probe.lua) -- same split as core/state_dump.lua.

local ADDON_NAME, Ledger = ...

-- One line for a probed global function/table: "NAME: absent" if it
-- doesn't exist, "NAME: present, call failed (err)" if calling it
-- raised an error, "NAME: present, no return value" if it exists and
-- returned nothing, or "NAME: present, value = ..." with every
-- returned value formatted with tostring (never guesses how many
-- values a call "should" return: ui/probe.lua already trimmed
-- trailing nils before handing this table over).
local function FormatAPILine(api)
    if not api.present then
        return api.name .. ": absent"
    end
    if api.callFailed then
        return string.format("%s: present, call failed (%s)", api.name, tostring(api.error))
    end
    if not api.values or #api.values == 0 then
        return api.name .. ": present, no return value"
    end

    local parts = {}
    for i, v in ipairs(api.values) do
        parts[i] = tostring(v)
    end
    return string.format("%s: present, value = %s", api.name, table.concat(parts, ", "))
end

local function FormatBuild(build)
    if not build or not build.present then
        return "  GetBuildInfo: absent"
    end
    if build.callFailed then
        return string.format("  GetBuildInfo: present, call failed (%s)", tostring(build.error))
    end
    return string.format("  GetBuildInfo: version=%s build=%s date=%s tocversion=%s",
        tostring(build.version), tostring(build.build), tostring(build.date), tostring(build.tocversion))
end

-- One line for what was done to the native xp bar's fill (see
-- ui/xp_bar.lua: Ledger.nativeFillInfo): "hidden" (the composition bar
-- fully replaces it), "overlay only" (couldn't hide it cleanly: the
-- composition bar just covers it, and the detail says why -- including
-- what the native bar is made of), "visible" or "n/a".
local function FormatNativeFill(info)
    if not info then
        return "  Native xp bar fill: not resolved yet (xp bar never applied this session)"
    end
    return string.format("  Native xp bar fill: %s (%s)", tostring(info.status), tostring(info.detail))
end

-- One line for the xp bar's resolved anchor (see ui/xp_bar.lua:
-- Ledger.xpBarAnchorInfo, set on every AnchorToNativeBar call): the
-- source description (which candidate matched, or "degraded" if none
-- did) plus the width/height actually resolved.
local function FormatAnchor(anchor)
    if not anchor then
        return "  XP bar anchor: not resolved yet (bar never drawn this session)"
    end
    return string.format("  XP bar anchor: %s (width=%s, height=%s)",
        tostring(anchor.source), tostring(anchor.width), tostring(anchor.height))
end

-- data shape (see ui/probe.lua: Ledger.GatherProbeData):
-- {
--   build           = { present=, callFailed=, error=, version=, build=, date=, tocversion= },
--   apis            = { { name=, present=, callFailed=, error=, values= }, ... },  -- fixed order
--   xpGainGlobals   = { "COMBATLOG_XPGAIN_...", ... },  -- sorted, may include the EXHAUSTION family too
--   chatInfoPresent = true|false,
--   xpBarAnchor     = { source=, width=, height= } | nil,
--   nativeFill      = { status=, detail= } | nil,
-- }
function Ledger.FormatProbe(data)
    data = data or {}
    local lines = { "Ledger probe:" }

    table.insert(lines, FormatBuild(data.build))

    table.insert(lines, "  APIs:")
    for _, api in ipairs(data.apis or {}) do
        table.insert(lines, "    " .. FormatAPILine(api))
    end

    local globals = data.xpGainGlobals or {}
    table.insert(lines, string.format("  COMBATLOG_XPGAIN_* globals: %d found", #globals))
    for _, name in ipairs(globals) do
        table.insert(lines, "    " .. name)
    end

    table.insert(lines, "  C_ChatInfo: " .. (data.chatInfoPresent and "present" or "absent"))

    table.insert(lines, FormatAnchor(data.xpBarAnchor))
    table.insert(lines, FormatNativeFill(data.nativeFill))

    return table.concat(lines, "\n")
end
