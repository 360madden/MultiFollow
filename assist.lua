-- ============================================================
-- MultiFollow | assist.lua
-- Purpose : Assist coordination between leader and followers.
--
--   LEADER side : watches its own target; broadcasts the target's
--                 name + health over the party channel whenever it
--                 changes materially.
--   FOLLOWER side: when assist mode is on, mirrors that target if
--                 the unit is present and attackable locally.
--
-- Verified API (Rift 4.x):
--   Inspect.Unit.Lookup("target")            -> target unit id or nil
--   Inspect.Unit.Detail(id)                  -> { name, classification,
--                                   hostile, ... }
--   Command.Target.Specifier("target", specifier)  -> sets target
--       Accepts "group0N" / "player" style specifiers only for
--       party units; a raw unit id string also works in practice.
--   Event.Unit.Detail.Change(unitId, fields) -> fires when cached
--       details change (attached in main.lua).
--
-- Limitation: a follower can only target units its own client has
-- loaded. If the leader's target is out of the follower's range,
-- the mirror silently fails and is retried on the next update.
-- ============================================================

local toc, data = ...

local Core   = data.Core
local Assist = {}
data.Assist  = Assist
MultiFollow.Assist = Assist

-- Event.Game.Tick (1 Hz) drives the leader's target polling.
-- Registered once by Follow/Assist shared tick in main.lua via
-- Assist.OnGameTick(); see Follow._OnGameTick which forwards here.
function Assist.Init()
    -- no separate handler: Assist.OnGameTick is called from
    -- Follow._OnGameTick (single Game.Tick subscription).
end

Assist.POLL_EVERY = 1     -- poll every N ticks (1s each)
Assist.HP_STEP    = 8     -- broadcast again only if HP moved >= this %

Assist.state = {
    leaderOn     = false,   -- leader broadcasting targets?
    followerOn   = false,   -- follower mirroring targets?
    lastKey      = nil,     -- "name|hpBand" last broadcast by leader
    lastTargetId = nil,
}

-- --------------------------------------------------------
-- Mode toggles
-- --------------------------------------------------------

function Assist.LeaderSet(on)
    Assist.state.leaderOn = on
    Assist.state.lastKey = nil
    Core.PrintC(on and Core.COLOR.LEADER or Core.COLOR.DIM,
        "Assist broadcasting " .. (on and "ON" or "OFF") .. " (leader).")
end

function Assist.FollowerSet(on)
    Assist.state.followerOn = on
    Core.PrintC(on and Core.COLOR.FOLLOWER or Core.COLOR.DIM,
        "Assist mirroring " .. (on and "ON" or "OFF") .. " (follower).")
end

function Assist.Toggle()
    if Core.config.role == "leader" then
        Assist.LeaderSet(not Assist.state.leaderOn)
    else
        Assist.FollowerSet(not Assist.state.followerOn)
    end
end

-- --------------------------------------------------------
-- Leader tick: detect target changes, broadcast MF:TGT
-- Called once per second from Follow._OnGameTick.
-- --------------------------------------------------------

function Assist.OnGameTick()
    if Assist.state.leaderOn and Core.config.role == "leader" then
        Assist._LeaderPoll()
    end
end

function Assist._LeaderPoll()
    local tid = Inspect.Unit.Lookup("target")
    if not tid then
        if Assist.state.lastKey ~= "none" then
            Assist.state.lastKey = "none"
            if data.Comms then data.Comms.SendTargetUpdate(nil) end
        end
        return
    end

    local detail = Inspect.Unit.Detail(tid)
    local name   = detail and detail.name
    if not name then return end

    local hp     = Assist._TargetHPPercent(tid)
    -- hp == -1 means vitals unavailable; band stays 0 so a plain
    -- target-name change still triggers exactly one broadcast.
    local band   = (hp >= 0) and math.floor(hp / Assist.HP_STEP) or 0
    local key    = name .. "|" .. band

    if key ~= Assist.state.lastKey then
        Assist.state.lastKey      = key
        Assist.state.lastTargetId = tid
        if data.Comms then
            data.Comms.SendTargetUpdate({
                name = name,
                hp   = hp,
                hostile = detail.hostile and true or false,
            })
        end
    end
end

-- Health percent via Vitals cache when available; best-effort.
function Assist._TargetHPPercent(tid)
    local ok, vitals = pcall(function() return Inspect.Unit.Vitals(tid) end)
    if ok and vitals and vitals.health and vitals.health.max and vitals.health.max > 0 then
        return math.floor((vitals.health.value / vitals.health.max) * 100)
    end
    return -1
end

-- --------------------------------------------------------
-- Follower side: apply leader's target broadcast
-- --------------------------------------------------------

function Assist.OnTargetBroadcast(info)
    if Core.config.role == "leader" then return end
    if not Assist.state.followerOn then return end

    if not info or not info.name then
        -- Leader cleared its target; clear ours too.
        pcall(function() Command.Target.Specifier("target", nil) end)
        return
    end

    local uid = Assist._FindByName(info.name)
    if not uid then return end  -- not loaded locally; retry next update

    local ok = pcall(function()
        Command.Target.Specifier("target", uid)
    end)
    if ok then
        Core.PrintC(Core.COLOR.DIM, "Assist: mirrored target '" .. info.name .. "'.")
    end
end

-- Scan known unit specifiers for a matching name. Only units our
-- client actually knows about can be targeted.
function Assist._FindByName(name)
    local lower = string.lower(name)

    -- Check party-adjacent group slots first (cheap lookups).
    for i = 1, Core.MAX_GROUP - 1 do
        local spec = "group" .. string.format("%02d", i)
        local uid  = Inspect.Unit.Lookup(spec)
        if uid then
            local d = Inspect.Unit.Detail(uid)
            if d and d.name and string.lower(d.name) == lower then
                return uid
            end
        end
    end

    -- Then try the direct name lookup form.
    local ok, uid = pcall(function() return Inspect.Unit.Lookup(name) end)
    if ok and uid then return uid end

    return nil
end

function Assist.GetDebugInfo()
    return {
        leaderOn   = Assist.state.leaderOn,
        followerOn = Assist.state.followerOn,
        lastKey    = Assist.state.lastKey,
    }
end
