-- Ledger - core/check.lua
-- Reconciliation for /ldg check: does the xp Ledger has RECORDED agree
-- with what the game says is REAL? Pure logic: does not use any WoW API,
-- it reads the data it's given (LedgerCharDB and the player's live
-- level/xp, gathered by ui/check_frame.lua) -- same split as
-- core/state_dump.lua. Time is NOT reconciled: there are no time
-- invariants, the activity counters are what they are (core/ticks.lua);
-- the last /played reading is only shown as information.
--
-- Two steps, both pure: Ledger.BuildCheck computes the findings as a
-- list of { status=, text= } lines (the status is what makes a line a
-- discrepancy, and what the verdict counts), and Ledger.FormatCheck
-- renders them to plain text with a textual mark per status. Marks are
-- text, not color codes, on purpose: the panel is an EditBox meant to be
-- copied with Ctrl+C, and escape codes would end up in the clipboard.

local ADDON_NAME, Ledger = ...

print("Ledger: core/check.lua")

-- status -> prefix of each rendered line. Only "bad" lines count as
-- discrepancies; ">>>" makes them stand out at a glance in a wall of
-- monospace text.
local MARKS = {
    info = "    ",
    ok   = "    [OK] ",
    skip = "    [??] ",
    bad  = ">>> [!!] ",
}

local function Signed(n)
    return string.format("%+d", n)
end

-- diff = recorded - real (or required). Says what a non-zero sign
-- means; nil when there's nothing to explain.
local function Interpretation(diff)
    if diff > 0 then
        return "POSITIVE (recorded > real): double counting"
    elseif diff < 0 then
        return "NEGATIVE (recorded < real): lost events"
    end
    return nil
end

-- Source names in Ledger.SRC_IDS order (kill, quest, explore, unknown,
-- ...), with any name not in that list appended alphabetically, so the
-- breakdown always reads in a stable order.
local function OrderedSources(bySource)
    local names = {}
    for name in pairs(bySource) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        local ia, ib = Ledger.SRC_IDS[a], Ledger.SRC_IDS[b]
        if ia and ib then return ia < ib end
        if ia then return true end
        if ib then return false end
        return a < b
    end)
    return names
end

local function SumValues(t)
    local total = 0
    for _, v in pairs(t) do total = total + v end
    return total
end

-- Ascending list of the level numbers present in `levels`.
local function SortedLevels(levels)
    local list = {}
    for level in pairs(levels or {}) do
        list[#list + 1] = level
    end
    table.sort(list)
    return list
end

-- charDB: the shape of LedgerCharDB ({ sessions=, levels= }).
-- player: { level=, xp= } -- UnitLevel("player")/UnitXP("player"), read
--   by the caller (this file never touches WoW API).
--
-- Returns { discrepancies = N, lines = { { status=, text= }, ... } }.
-- status is one of "title", "section", "info", "ok", "bad" (a
-- discrepancy, counted in `discrepancies`) or "skip" (couldn't be
-- verified for lack of data: not a discrepancy, but never silently
-- passed as OK either). "title" is always the first line and carries the
-- global verdict.
function Ledger.BuildCheck(charDB, player)
    local body = {}
    local discrepancies = 0

    local function add(status, text)
        if status == "bad" then discrepancies = discrepancies + 1 end
        body[#body + 1] = { status = status, text = text }
    end

    local sessions = charDB.sessions or {}
    local levels   = charDB.levels or {}

    ------------------------------------------------------------------
    -- Current level: recorded (sum of ALL of its sessions, never just
    -- the active one) vs real (UnitXP).
    ------------------------------------------------------------------
    add("section", "Current level")

    local recorded = Ledger.TotalXPAcrossSessions(sessions, true) -- raw xp: never affected by includeRested
    local real     = player.xp
    local initial  = (sessions[1] and sessions[1].initialXP) or 0
    local events   = 0
    for _, session in ipairs(sessions) do
        events = events + Ledger.EventCount(session)
    end

    add("info", string.format("Level %d (%d session(s), %d event(s))", player.level, #sessions, events))
    if sessions[1] and sessions[1].level ~= player.level then
        add("bad", string.format(
            "The sessions belong to level %s but the player is level %d -- a level change was not tracked",
            tostring(sessions[1].level), player.level))
    end
    add("info", string.format("Recorded xp (sum of the level's sessions): %d", recorded))
    add("info", string.format("Real xp (UnitXP): %d", real))

    -- The gray initial segment is xp the player already had before
    -- tracking started: it's never in the recorded series, so a level
    -- adopted mid-way is EXPECTED to read recorded < real by exactly
    -- that much. The verdict uses the difference with it discounted;
    -- the raw one is shown for reference only.
    local diff
    if initial > 0 then
        add("info", string.format("Initial gray segment (xp before tracking started): %d", initial))
        add("info", string.format("Difference without discounting it: %s (informational, expected to be %s)",
            Signed(recorded - real), Signed(-initial)))
        diff = recorded + initial - real
    else
        diff = recorded - real
    end

    local diffLabel = (initial > 0) and "Difference discounting the initial segment (recorded + initial - real)"
        or "Difference (recorded - real)"
    local interpretation = Interpretation(diff)
    if interpretation then
        add("bad", string.format("%s: %s -- %s", diffLabel, Signed(diff), interpretation))
    else
        add("ok", string.format("%s: %s", diffLabel, Signed(diff)))
    end

    ------------------------------------------------------------------
    -- Breakdown of the current level by source.
    ------------------------------------------------------------------
    add("section", "Current level: xp by source")
    local bySource = Ledger.XPBySourceAcrossSessions(sessions)
    local sources = OrderedSources(bySource)
    if #sources == 0 then
        add("info", "(no xp recorded on this level yet)")
    else
        local total = SumValues(bySource)
        for _, src in ipairs(sources) do
            local xp  = bySource[src]
            local pct = (total > 0) and (xp / total * 100) or 0
            if src == "unknown" and xp > 0 then
                add("bad", string.format(
                    "unknown: %d xp (%.1f%%) -- events whose source could not be paired", xp, pct))
            else
                add("info", string.format("%s: %d xp (%.1f%%)", src, xp, pct))
            end
        end
    end

    ------------------------------------------------------------------
    -- Closed levels: what each one recorded vs what it required.
    ------------------------------------------------------------------
    local closed = SortedLevels(levels)

    add("section", "Closed levels: recorded xp vs required")
    if #closed == 0 then
        add("info", "(no closed levels yet)")
    end
    for _, level in ipairs(closed) do
        local entry = levels[level]
        -- bySource is always the total xp as-is, whereas entry.totalXP
        -- depends on the includeRested toggle in force at close time
        -- (which isn't stored): summing bySource is the toggle-proof
        -- way to get the level's real recorded total.
        local levelRecorded = SumValues(entry.bySource or {})
        local levelInitial  = entry.initialXP or 0
        local required      = entry.xpRequired

        if not required then
            add("skip", string.format(
                "Level %d: recorded %d, but the required xp was not stored (closed before it was tracked) -- cannot verify",
                level, levelRecorded))
        else
            local levelDiff = levelRecorded + levelInitial - required
            local detail = string.format("recorded %d%s vs required %d",
                levelRecorded, (levelInitial > 0) and string.format(" + initial %d", levelInitial) or "", required)
            local why = Interpretation(levelDiff)
            if why then
                add("bad", string.format("Level %d: %s: %s -- %s", level, detail, Signed(levelDiff), why))
            else
                add("ok", string.format("Level %d: %s", level, detail))
            end
        end
    end

    ------------------------------------------------------------------
    -- Time: INFORMATION ONLY, never a discrepancy. The activity mix is
    -- shown as percentages of the samples (never absolute time), and the
    -- last /played reading is shown next to the sample total it was
    -- taken against, with their difference -- a difference between the
    -- two is expected (the sampler only ticks while the client runs) and
    -- is presented as information, not as an error.
    ------------------------------------------------------------------
    add("section", "Time (information only)")

    local levelTicks = charDB.levelTicks
    add("info", "Level activity, % of samples: " .. Ledger.FormatTickSummary(levelTicks))
    local activeSession = sessions[#sessions]
    if activeSession then
        add("info", "Session activity, % of samples: " .. Ledger.FormatTickSummary(activeSession.ticks))
    end

    local played = charDB.played
    if not played then
        add("info", "/played: no reading yet (it is requested on login and when this window opens)")
    elseif played.level ~= player.level then
        add("info", string.format(
            "/played: last reading is from level %s, the player is now level %d -- refresh to read again",
            tostring(played.level), player.level))
    else
        add("info", string.format(
            "/played, this level: %ds played vs %d samples at that moment, difference %+d",
            played.seconds, played.samples, played.seconds - played.samples))
        add("info", "  (information, not an error: samples only run while the client does)")
    end

    add("section", "Notes")
    add("info", "Xp still waiting to pair with its source (about 1s) can read as a transient negative")
    add("info", "difference right after a kill or a ding: refresh to re-check before trusting it.")

    local verdict
    if discrepancies == 0 then
        verdict = "Ledger check: ALL OK"
    else
        verdict = string.format("Ledger check: %d DISCREPANC%s FOUND", discrepancies,
            discrepancies == 1 and "Y" or "IES")
    end

    local lines = { { status = "title", text = verdict } }
    for _, line in ipairs(body) do
        lines[#lines + 1] = line
    end
    return { discrepancies = discrepancies, lines = lines }
end

-- Renders a Ledger.BuildCheck result to plain text: one line per entry,
-- a blank line and "== name ==" heading before each section, and the
-- status mark in front of every verdict line (see MARKS).
function Ledger.FormatCheck(result)
    local out = {}
    for _, line in ipairs(result.lines) do
        if line.status == "title" then
            out[#out + 1] = line.text
        elseif line.status == "section" then
            out[#out + 1] = ""
            out[#out + 1] = "== " .. line.text .. " =="
        else
            out[#out + 1] = (MARKS[line.status] or MARKS.info) .. line.text
        end
    end
    return table.concat(out, "\n")
end
