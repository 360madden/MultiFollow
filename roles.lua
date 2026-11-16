-- ============================================================
-- MultiFollow | roles.lua
-- Purpose : Role management - leader / follower / unassigned.
-- ============================================================

local toc, data = ...

local Core  = data.Core
local Roles = {}
data.Roles  = Roles
MultiFollow.Roles = Roles

local VALID_ROLES = { leader = true, follower = true, unassigned = true }
Roles._startupReminderShown = false

function Roles.GetRole()
    return Core.config.role or "unassigned"
end

-- Low-level setter - no side-effects beyond saving.
function Roles.SetRole(role)
    if not VALID_ROLES[role] then
        Core.PrintC(Core.COLOR.ERROR, "Unknown role '" .. tostring(role) .. "'. Valid: leader, follower, unassigned.")
        return false
    end
    Core.config.role   = role
    MultiFollowDB.role = role
    return true
end

-- --------------------------------------------------------
-- BecomeLeader
-- Sets role, saves, sends silent direct messages to all
-- known followers via Comms.SendLeaderAnnounce.
-- --------------------------------------------------------

function Roles.BecomeLeader()
    Roles.SetRole("leader")

    local myName = Core.state.playerName or "unknown"
    Core.state.leaderName    = myName
    Core.config.leaderName   = myName
    MultiFollowDB.leaderName = myName

    Core.PrintC(Core.COLOR.LEADER, "You are the leader: " .. myName)

    if data.Comms then
        data.Comms.SendLeaderAnnounce()
    end
end

-- --------------------------------------------------------
-- BecomeFollower
-- Sets role, optionally stores leader name.
-- --------------------------------------------------------

function Roles.BecomeFollower(leaderName)
    Roles.SetRole("follower")

    if leaderName then
        Core.state.leaderName    = leaderName
        Core.config.leaderName   = leaderName
        MultiFollowDB.leaderName = leaderName
    end

    Core.PrintC(Core.COLOR.FOLLOWER, "Role: follower | Leader: " .. (leaderName or "(pending)"))
end

function Roles.SendReady()
    if Roles.GetRole() == "leader" then
        Core.PrintC(Core.COLOR.WARN, "Leader cannot send follower ready.")
        return false
    end

    local myName = Core.state.playerName
    local leaderName = Core.state.leaderName or Core.config.leaderName

    if not leaderName or leaderName == "" then
        Core.PrintC(Core.COLOR.ERROR, "No saved leader. Use /mf follow <leaderName> first.")
        return false
    end

    if myName and string.lower(myName) == string.lower(leaderName) then
        Core.PrintC(Core.COLOR.ERROR, "Saved leader matches this character. Check your role setup.")
        return false
    end

    if data.Comms then
        data.Comms.SendFollowerReady()
        Core.PrintC(Core.COLOR.FOLLOWER, "Follower ready sent for leader " .. tostring(leaderName) .. ".")
        return true
    end

    Core.PrintC(Core.COLOR.ERROR, "Comms not initialized.")
    return false
end

function Roles.MaybePrintStartupReminder()
    if Roles._startupReminderShown then return end
    if Roles.GetRole() ~= "follower" then return end

    local myName = Core.state.playerName
    local leaderName = Core.state.leaderName or Core.config.leaderName

    if not leaderName or leaderName == "" then return end
    if (Core.state.groupCount or 0) > 0 then return end

    if myName and string.lower(myName) == string.lower(leaderName) then
        return
    end

    Roles._startupReminderShown = true
    Core.PrintC(Core.COLOR.FOLLOWER,
        "Saved follower setup found. Leader: " .. tostring(leaderName) .. ".")
    Core.PrintC(Core.COLOR.DIM,
        "Not currently grouped. If needed, run /mf ready and have the leader /invite "
            .. tostring(myName or "this character") .. ".")
end

-- --------------------------------------------------------
-- OnLeaderAnnounce
-- Fired by Comms when MF:LEAD arrives via proximity broadcast.
-- Auto-configures this character as a follower and replies.
-- Leaders silently ignore this (two leaders on same session
-- is not a supported configuration).
-- --------------------------------------------------------

function Roles.OnLeaderAnnounce(leaderName)
    if Core.config.role == "leader" then return end

    Roles.BecomeFollower(leaderName)

    if data.Comms then
        data.Comms.SendFollowerReady()
    end
end

-- --------------------------------------------------------
-- OnFollowerReady
-- Leader side: register the ready follower so /mf status and
-- the invite checklist stay in sync. Dedupe/cap handled by
-- Comms._RegisterFollower.
-- --------------------------------------------------------

function Roles.OnFollowerReady(followerName)
    if data.Comms then
        data.Comms._RegisterFollower(followerName)
    end
end

-- --------------------------------------------------------
-- Unassign
-- Clears role + leader association and tells any listening
-- counterpart to drop us from its pending list.
-- --------------------------------------------------------

function Roles.Unassign()
    local wasRole = Roles.GetRole()

    if wasRole == "follower" and data.Comms then
        data.Comms.SendBye()
    end

    if wasRole == "leader" then
        if data.Comms then data.Comms.ClearPending() end
        if data.Follow then data.Follow.LeaderBroadcastSet(false) end
        if data.Assist then data.Assist.LeaderSet(false) end
    else
        if data.Follow then data.Follow.Stop(true) end
        if data.Assist then data.Assist.FollowerSet(false) end
    end

    Core.state.leaderName    = nil
    Core.config.leaderName   = nil
    MultiFollowDB.leaderName = nil
    Roles.SetRole("unassigned")
    Roles._startupReminderShown = false

    Core.PrintC(Core.COLOR.DIM, "Role cleared. This character is unassigned.")
end

-- --------------------------------------------------------
-- StopAll
-- /mf stop on either side: followers halt following; leader
-- additionally halts all telemetry/command modes.
-- --------------------------------------------------------

function Roles.StopAll()
    if Core.config.role == "leader" then
        -- Tell every follower to stop before we silence ourselves.
        if data.Comms then
            data.Comms.SendPartyCommand("stop")
            data.Comms.ClearPending()
        end
        if data.Follow then data.Follow.LeaderBroadcastSet(false) end
        if data.Assist then data.Assist.LeaderSet(false) end
        Core.PrintC(Core.COLOR.WARN, "Leader halted: stop sent to party.")
    else
        if data.Follow then data.Follow.Stop() end
        if data.Assist then data.Assist.FollowerSet(false) end
    end
end
