-- ============================================================
-- MultiFollow | group.lua
-- Purpose : Party member detection and registry.
--           Scans group01..group04 specifiers, tracks joins
--           and leaves via availability events.
--           Does NOT send messages - delegates to comms.lua.
-- ============================================================
-- Confirmed pattern from Gadgets/wtLibUnitDatabase:
--   Inspect.Unit.Lookup("group" .. string.format("%02d", i))
--   returns the unit ID for that group slot, or nil if empty.
--
-- Event.Unit.Availability.Full(units)
--   fires when units become visible/available.
--   units = table { [unitId] = specifier or false }
--
-- Event.Unit.Availability.None(units)
--   fires when units leave availability entirely.
--   units = table { [unitId] = specifier or false }
-- ============================================================

local toc, data = ...

local Core  = data.Core
local Group = {}
data.Group  = Group
MultiFollow.Group = Group

-- ============================================================
-- Scan
-- Reads all group01..group04 slots and rebuilds Core.state.group.
-- Safe to call at any time. Called on init and after each
-- availability event that involves group specifiers.
-- ============================================================

function Group.Scan()
    local found = {}
    local count = 0

    for i = 1, Core.MAX_GROUP - 1 do  -- MAX_GROUP=5; 4 slots besides self
        local spec  = "group" .. string.format("%02d", i)
        local uid   = Inspect.Unit.Lookup(spec)

        if uid then
            local detail = Inspect.Unit.Detail(uid)
            local name   = detail and detail.name or ("group" .. i)
            found[spec]  = { name = name, unitId = uid }
            count        = count + 1
        end
    end

    Core.state.group      = found
    Core.state.groupCount = count
end

-- ============================================================
-- OnAvailabilityFull
-- Called from main.lua when Event.Unit.Availability.Full fires.
-- Only re-scans if any of the newly available units are group
-- specifiers - avoids unnecessary work for unrelated units.
-- ============================================================

function Group.OnAvailabilityFull(handle, units)
    if Group._AnyGroupSpecifier(units) then
        Group.Scan()
        Group._OnGroupChanged("join")
    end
end

-- ============================================================
-- OnAvailabilityNone
-- Called from main.lua when Event.Unit.Availability.None fires.
-- ============================================================

function Group.OnAvailabilityNone(handle, units)
    if Group._AnyGroupSpecifier(units) then
        Group.Scan()
        Group._OnGroupChanged("leave")
    end
end

-- ============================================================
-- _AnyGroupSpecifier  (private)
-- Returns true if the units table contains any "group0N" entry.
-- ============================================================

function Group._AnyGroupSpecifier(units)
    if type(units) ~= "table" then return false end
    for _, spec in pairs(units) do
        if type(spec) == "string" and spec:match("^group%d%d$") then
            return true
        end
    end
    return false
end

-- ============================================================
-- _OnGroupChanged  (private)
-- Prints group status and, if we are the leader, re-broadcasts
-- our leader announcement so any newly-joined follower learns
-- who the leader is immediately.
-- ============================================================

function Group._OnGroupChanged(event)
    local count = Core.state.groupCount
    Core.PrintC(Core.COLOR.DIM, "Group update (" .. event .. "): " .. count .. " member(s) in party.")

    -- BUG FIX 2: Do NOT call SendLeaderAnnounce() here.
    -- SendLeaderAnnounce resets _pendingFollowers, which would wipe
    -- the /invite list mid-formation every time a member joins.
    -- Also unnecessary: the member was already configured as a follower
    -- before being invited. Once in party, the party channel is used.
    -- A party-channel re-announce will be added in Pass 3.
end

-- ============================================================
-- GetMemberNames
-- Returns a list of member name strings for status display.
-- ============================================================

function Group.GetMemberNames()
    local names = {}
    for _, member in pairs(Core.state.group) do
        table.insert(names, member.name)
    end
    return names
end
