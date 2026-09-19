-- Ledger - core/series.lua
-- Declares the data model's time series (flat arrays inside a session)
-- and gives the generic helpers to read and write them. Pure logic:
-- does not use any WoW API.
--
-- Adding a new series (gold, reputation, gathering loot...) is just one
-- more entry in Ledger.SERIES; neither the text serializer nor the
-- debug panel (nor anything in core/) should ever reference a specific
-- series' field name or stride.

local ADDON_NAME, Ledger = ...

print("Ledger: core/series.lua")

Ledger.SERIES = {
    xp = { key = "e", stride = 4, fields = { "off", "xp", "src", "rested" } },
    -- xp: xp is the TOTAL xp of the event (UnitXP delta); rested is the
    -- part of that xp that came from the rested bonus (0 if there was
    -- no bonus). xp - rested >= 0 always holds (see core/events.lua:
    -- AddEvent, which clamps rested if it would come in higher than
    -- xp). The src field is persisted as the numeric ID below
    -- (Ledger.SRC_IDS), not as text: the string<->id translation lives
    -- at the persistence boundary (core/events.lua: AddEvent when
    -- writing, XPBySource when reading; core/xp_bar.lua:
    -- MergeConsecutive; core/state_dump.lua: FormatSession) so the rest
    -- of the code (matcher, chat_patterns, palette) keeps working with
    -- the text name.
    -- future: gold (stride 3), rep (stride 4, with a faction field),
    --         loot (stride 3).
    -- There is deliberately no series for the per-second activity
    -- sample: it is never stored as a series, only as running counters
    -- (core/ticks.lua).
}

-- Numeric enum for the xp series' src field. Adding a new source is
-- just one more entry here (and nothing else: SRC_IDS derives itself).
-- "previous" is never actually persisted (it's the synthetic segment
-- for xp earned before tracking started, see Ledger.BAR_INITIAL_SRC in
-- core/xp_bar.lua) but it still lives here so this is the single place
-- with the full list of known sources.
Ledger.SRC_NAMES = {
    [1] = "kill",
    [2] = "quest",
    [3] = "explore",
    [4] = "unknown",
    [5] = "previous",
}
Ledger.SRC_IDS = {}
for id, name in pairs(Ledger.SRC_NAMES) do
    Ledger.SRC_IDS[name] = id
end

-- (1-based) index of the `name` field within a series record, or nil
-- if that series has no such field.
function Ledger.SeriesFieldIndex(seriesDef, name)
    for i, field in ipairs(seriesDef.fields) do
        if field == name then return i end
    end
    return nil
end

-- Appends a record (stride values, in the order of seriesDef.fields) to
-- the series' flat array inside session.
function Ledger.AppendRecord(session, seriesDef, ...)
    local arr = session[seriesDef.key]
    if not arr then
        arr = {}
        session[seriesDef.key] = arr
    end

    local values = { ... }
    for i = 1, seriesDef.stride do
        arr[#arr + 1] = values[i]
    end
end

-- Number of stored records.
function Ledger.RecordCount(session, seriesDef)
    local arr = session[seriesDef.key]
    if not arr then return 0 end
    return #arr / seriesDef.stride
end

-- Returns record `index` (1-based) as a table keyed by field name, or
-- nil if it doesn't exist.
function Ledger.ReadRecord(session, seriesDef, index)
    local arr = session[seriesDef.key]
    if not arr then return nil end

    local base = (index - 1) * seriesDef.stride
    if index < 1 or base + seriesDef.stride > #arr then return nil end

    local record = {}
    for i, field in ipairs(seriesDef.fields) do
        record[field] = arr[base + i]
    end
    return record
end

-- Concatenates a series' flat array across several sessions, in the
-- given order (assumed chronological: `sessions` is already ordered by
-- whoever calls this, like the real list of a level's sessions). Used
-- to aggregate data from ALL of a level's sessions instead of just the
-- active one (e.g. the xp composition bar).
function Ledger.ConcatSeries(sessions, seriesDef)
    local combined = {}
    for _, session in ipairs(sessions) do
        local arr = session[seriesDef.key]
        if arr then
            for _, value in ipairs(arr) do
                combined[#combined + 1] = value
            end
        end
    end
    return combined
end
