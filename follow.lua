-- ============================================================
-- MultiFollow | follow.lua
-- Purpose : Follower-side movement engine.
--           When "follow mode" is active, this character walks
--           toward the leader using Command.Unit.Travel.Distance.
--
-- Verified API (Rift 4.x):
--   Inspect.Unit.Lookup("player")            -> player unit id
--   Inspect.Unit.Detail(unitId)              -> { name, x, y, z,
--                                   location = { instance, zone }, ... }
--   Command.Unit.Travel.Distance(specifierOrId, x, y, z, maxDistance,
--                              tolerance, callback)
--       -> returns promise-like handle; callback receives a status
--          table: { code = "success"|"failure", reason = "...", ... }
--
-- NOTE ON LIMITATIONS
--   Rift's Lua sandbox cannot teleport or force-movement other
--   clients. The best available primitive is travel-to-coordinates
--   on our OWN player unit. Followers therefore move themselves
--   toward coordinates the leader broadcasts over the party channel.
--   This is "coordinated auto-follow", not puppeteering.
-- ============================================================

local toc, data = ...

local Core   = data.Core
local Follow = {}
data.Follow  = Follow
MultiFollow.Follow = Follow

-- Rift's addon clock event: Event.Game.Tick fires once per second.
-- This is the canonical timer source (no Command.Effect.Schedule).
-- The single subscription drives follower evaluation, leader
-- position telemetry, and leader assist polling.
function Follow.Init()
    if not Follow._tickAttached then
        Command.Event.Attach(Event.Game.Tick, Follow._OnGameTick,
            Core.IDENTIFIER .. "_GameTick")
        Follow._tickAttached = true
    end
end

-- --------------------------------------------------------
-- Tunables
-- --------------------------------------------------------

Follow.TICK_MS        = 1000   -- re-check interval while moving
Follow.START_TOLERANCE = 30    -- stop threshold for travel call (m)
Follow.RECHECK_SLOP    = 5     -- if within START_TOLERANCE+RECHECK_SLOP, don't re-issue
Follow.MAX_DROP        = 200   -- ignore target coords farther than this (likely stale/other map)

-- --------------------------------------------------------
-- Runtime state
-- --------------------------------------------------------

Follow.state = {
    active      = false,
    target      = nil,   -- { x, y, z, instance, seq }
    lastSeq     = 0,
    traveling   = false,
    ticks       = 0,     -- Event.Game.Tick counter since activation
    lastSent    = 0,     -- leader: tick position was broadcast on
    dropCount   = 0,
}

-- --------------------------------------------------------
-- Leader-side state: broadcasting our own coordinates
-- --------------------------------------------------------

Follow.leaderBroadcast = false

function Follow.LeaderBroadcastSet(on)
    Follow.leaderBroadcast = on
    Core.PrintC(on and Core.COLOR.LEADER or Core.COLOR.DIM,
        "Position broadcasting " .. (on and "ON" or "OFF") .. " (leader).")
end

-- Called from the per-second Game.Tick handler when this client
-- is the leader with broadcasting enabled.
function Follow._BroadcastSelfPosition()
    local pid = Inspect.Unit.Lookup("player")
    local me  = pid and Inspect.Unit.Detail(pid)
    if not me or not me.x or not me.z then return end

    local inst = me.location and me.location.instance or nil
    if data.Comms then
        data.Comms.SendPosition(me.x, me.y or 0, me.z, inst)
    end
end

-- --------------------------------------------------------
-- Leader specifier lookup
-- The leader is "player" when we ARE the leader; otherwise we
-- find the party slot whose name matches Core.state.leaderName.
-- Returns specifier string ("group0N") or unit id, or nil.
-- --------------------------------------------------------

function Follow.LeaderSpecifier()
    local myName    = Core.state.playerName
    local leaderNm  = Core.state.leaderName or Core.config.leaderName

    if not leaderNm then return nil end
    if myName and string.lower(myName) == string.lower(leaderNm) then
        return "player"
    end

    for spec, member in pairs(Core.state.group) do
        if member.name and string.lower(member.name) == string.lower(leaderNm) then
            return spec
        end
    end
    return nil
end

-- --------------------------------------------------------
-- Start / Stop
-- --------------------------------------------------------

function Follow.Start(silent)
    if Follow.state.active then return true end

    local spec = Follow.LeaderSpecifier()
    if not spec then
        Core.PrintC(Core.COLOR.ERROR,
            "Cannot start follow: leader not found in party (or no leader saved).")
        return false
    end

    Follow.state.active = true
    Follow.state.ticks  = 0
    if not silent then
        Core.PrintC(Core.COLOR.FOLLOWER, "Follow mode ON - tracking leader.")
    end
    return true
end

function Follow.Stop(silent)
    if not Follow.state.active then return false end

    Follow.state.active = false
    Follow.state.traveling = false
    Follow.state.target = nil

    -- Halt our own movement cleanly.
    pcall(function() Command.Unit.Movement.Halt("player") end)

    if not silent then
        Core.PrintC(Core.COLOR.WARN, "Follow mode OFF.")
    end
    return true
end

function Follow.Toggle()
    if Follow.state.active then
        Follow.Stop()
    else
        Follow.Start()
    end
end

function Follow.IsActive()
    return Follow.state.active
end

-- --------------------------------------------------------
-- OnLeaderPosition
-- Called by Comms when MF:POS arrives. Coordinates come from
-- the leader's own Inspect.Unit.Detail("player").
-- --------------------------------------------------------

function Follow.OnLeaderPosition(x, y, z, instance, seq)
    if not Follow.state.active then return end

    seq = tonumber(seq) or 0
    if seq ~= 0 and seq <= Follow.state.lastSeq then
        return  -- out-of-order; newer data already applied
    end
    Follow.state.lastSeq = seq
    Follow.state.target  = { x = x, y = y, z = z, instance = instance, seq = seq }

    if not Follow.state.traveling then
        Follow._Evaluate()
    end
end

-- --------------------------------------------------------
-- _OnGameTick
-- Event.Game.Tick handler (1 Hz), attached via Follow.Init().
--  * Leader + broadcasting on -> send our coordinates.
--  * Follower + follow active -> periodic re-evaluation so we
--    keep chasing a moving leader even between POS messages.
-- --------------------------------------------------------

local globalTicks = 0

function Follow._OnGameTick(handle)
    globalTicks = globalTicks + 1

    -- Leader telemetry
    if Follow.leaderBroadcast and Core.config.role == "leader" then
        Follow._BroadcastSelfPosition()
    end

    -- Follower loop
    if Follow.state.active then
        Follow.state.ticks = Follow.state.ticks + 1
        if not Follow.state.traveling and Follow.state.ticks % 2 == 0 then
            Follow._Evaluate()
        end
    end

    -- Leader assist polling (shared clock, forwarded to assist.lua)
    if data.Assist and data.Assist.OnGameTick then
        data.Assist.OnGameTick()
    end
end

-- --------------------------------------------------------
-- _Evaluate
-- Compare self position vs target; issue travel if needed.
-- --------------------------------------------------------

function Follow._Evaluate()
    local st = Follow.state
    if not st.active or not st.target then return end

    local pid  = Inspect.Unit.Lookup("player")
    local me   = pid and Inspect.Unit.Detail(pid)
    if not me or not me.x then
        Core.PrintC(Core.COLOR.DIM, "Follow: self position unavailable.")
        return
    end

    local t = st.target

    -- Zone guard: ignore targets from a different instance (stale msg).
    if t.instance and me.location and me.location.instance then
        if tostring(t.instance) ~= tostring(me.location.instance) then
            return
        end
    end

    local dx, dy, dz = t.x - me.x, (t.y or 0) - (me.y or 0), t.z - me.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

    if dist > Follow.MAX_DROP then
        st.dropCount = st.dropCount + 1
        if st.dropCount % 10 == 1 then
            Core.PrintC(Core.COLOR.WARN,
                ("Follow: target %.0fm away - ignoring (out of range)."):format(dist))
        end
        return
    end

    if dist <= Follow.START_TOLERANCE + Follow.RECHECK_SLOP then
        -- Close enough: consider arrived.
        if st.traveling then
            st.traveling = false
            st.arrivedAt = os.clock()
            Core.PrintC(Core.COLOR.DIM,
                ("Follow: arrived near leader (%.0fm)."):format(dist))
        end
        return
    end

    Follow._TravelTo(t.x, t.y or me.y or 0, t.z)
end

-- --------------------------------------------------------
-- _TravelTo
-- Issue the actual movement command on our own player.
-- --------------------------------------------------------

function Follow._TravelTo(x, y, z)
    local st = Follow.state
    if st.traveling then return end
    st.traveling = true

    local ok, err = pcall(function()
        Command.Unit.Travel.Distance(
            "player", x, y, z,
            Follow.MAX_DROP,
            Follow.START_TOLERANCE,
            function(result)
                st.traveling = false
                if result and result.code and result.code ~= "success" then
                    Core.PrintC(Core.COLOR.WARN,
                        "Follow: travel failed (" .. tostring(result.reason or result.code) .. ").")
                end
            end
        )
    end)

    if not ok then
        st.traveling = false
        Core.PrintC(Core.COLOR.ERROR,
            "Follow: travel API unavailable: " .. tostring(err))
    end
end

-- --------------------------------------------------------
-- Snapshot for /mf debug
-- --------------------------------------------------------

function Follow.GetDebugInfo()
    local st = Follow.state
    return {
        active    = st.active,
        traveling = st.traveling,
        lastSeq   = st.lastSeq,
        hasTarget = st.target ~= nil,
        drops     = st.dropCount,
    }
end
