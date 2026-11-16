-- ============================================================
-- MultiFollow | ui.lua
-- Purpose : Slash-command registration and chat output.
-- ============================================================

local toc, data = ...

local Core  = data.Core
local Roles = data.Roles
local UI    = {}
data.UI     = UI
MultiFollow.UI = UI

function UI.Init()
    local slashEvent = Command.Slash.Register("mf")
    if slashEvent == nil then
        Core.PrintC(Core.COLOR.ERROR, "WARNING: /mf could not be registered.")
        return
    end
    Command.Event.Attach(slashEvent, UI._OnSlash, Core.IDENTIFIER .. "_Slash")
end

function UI._OnSlash(handle, args)
    args = args and args:match("^%s*(.-)%s*$") or ""
    local cmd, rest = args:match("^(%S+)%s*(.*)")
    cmd  = cmd  and cmd:lower()               or ""
    rest = rest and rest:match("^%s*(.-)%s*$") or ""

    if cmd == "" or cmd == "help" then
        UI.PrintHelp()

    elseif cmd == "lead" then
        -- Sets this window as leader, scans friends list for
        -- online friends in same zone, sends silent MF:LEAD to each.
        data.Roles.BecomeLeader()

    elseif cmd == "follow" then
        -- Manual follower set. Not usually needed - leader's announce
        -- auto-configures followers who are running MultiFollow.
        if rest ~= "" then
            data.Roles.BecomeFollower(rest)
            data.Roles.SendReady()
        else
            data.Roles.BecomeFollower(nil)
        end

    elseif cmd == "ready" then
        data.Roles.SendReady()

    elseif cmd == "go" then
        -- Leader: arm the whole setup (positions + follow + assist).
        UI.CommandGo()

    elseif cmd == "stop" then
        -- Either side: halt following / broadcasting.
        data.Roles.StopAll()

    elseif cmd == "followmode" or cmd == "fm" then
        -- Follower-local toggle of auto-follow (no comms needed).
        if data.Follow then data.Follow.Toggle() end

    elseif cmd == "assist" then
        if rest ~= "" then
            local on = (rest == "on")
            if Core.config.role == "leader" then
                data.Assist.LeaderSet(on)
            else
                data.Assist.FollowerSet(on)
            end
        else
            data.Assist.Toggle()
        end

    elseif cmd == "unassign" then
        data.Roles.Unassign()

    elseif cmd == "scan" then
        -- Preview which friends would be contacted by /mf lead.
        UI.PrintFriendScan()

    elseif cmd == "status" then
        UI.PrintStatus()

    elseif cmd == "debug" then
        UI.PrintDebug()

    else
        Core.PrintC(Core.COLOR.WARN, "Unknown command '" .. cmd .. "'. Type /mf help.")
    end
end

-- --------------------------------------------------------
-- CommandGo  (leader)
-- Arms the coordinated session: starts position broadcasting,
-- then tells all party followers to begin following and
-- mirroring the leader's target.
-- --------------------------------------------------------

function UI.CommandGo()
    if Core.config.role ~= "leader" then
        Core.PrintC(Core.COLOR.WARN,
            "/mf go is a leader command. Followers: use /mf fm to toggle follow locally.")
        return
    end

    if (Core.state.groupCount or 0) == 0 then
        Core.PrintC(Core.COLOR.ERROR,
            "No party members yet. Invite your followers first (see /mf status).")
        return
    end

    data.Follow.LeaderBroadcastSet(true)
    data.Comms.SendPartyCommand("follow-on")
    data.Comms.SendPartyCommand("assist-on")
    data.Assist.LeaderSet(true)

    Core.PrintC(Core.COLOR.SUCCESS,
        "GO: broadcasting positions, followers engaged (" ..
        Core.state.groupCount .. " in party).")
end

-- --------------------------------------------------------
-- PrintHelp
-- --------------------------------------------------------

function UI.PrintHelp()
    local lines = {
        "MultiFollow v" .. Core.VERSION .. " commands:",
        "  SETUP",
        "  /mf lead          - THIS window becomes leader; announce",
        "                      to nearby MultiFollow characters.",
        "  /mf follow        - become follower (auto via leader announce).",
        "  /mf follow <name> - save leader name and send ready now.",
        "  /mf ready         - re-send follower ready to saved leader.",
        "  /mf unassign      - clear role and leader association.",
        "",
        "  OPERATION (after party is formed)",
        "  /mf go            - LEADER: start position broadcast and",
        "                      order all followers to follow+assist.",
        "  /mf stop          - halt following/broadcasting (either side).",
        "  /mf fm            - FOLLOWER: toggle auto-follow locally.",
        "  /mf assist [on|off] - toggle assist (role-aware).",
        "",
        "  DIAGNOSTICS",
        "  /mf scan          - preview which friends are detectable.",
        "  /mf status        - show group and follower state.",
        "  /mf debug         - print detailed addon state.",
        "  /mf help          - show this message.",
    }
    for _, line in ipairs(lines) do Core.PrintC(Core.COLOR.DIM, line) end
end

-- --------------------------------------------------------
-- PrintFriendScan
-- Shows which friends are online and in the same zone
-- without actually sending any messages.
-- --------------------------------------------------------

function UI.PrintFriendScan()
    if not data.Comms then
        Core.PrintC(Core.COLOR.ERROR, "Comms not initialized.")
        return
    end

    -- Raw dump for debugging: show every friend and their status/zone
    local friends = Inspect.Social.Friend.List()
    if not friends then
        Core.PrintC(Core.COLOR.ERROR, "Friend list returned nil.")
        return
    end

    local count = 0
    for k, v in pairs(friends) do
        local friendName = (type(k) == "string") and k or
                           (type(v) == "string") and v or nil
        if friendName then
            local detail = Inspect.Social.Friend.Detail(friendName)
            local status = detail and (detail.status or "offline") or "no detail"
            local zone   = detail and (detail.zone   or "nil")    or "nil"
            local isOnline = (status == "online" or status == "afk")
            local color = isOnline and Core.COLOR.FOLLOWER or Core.COLOR.DIM
            Core.PrintC(color, "  " .. friendName .. " | status=" .. status .. " | zone=" .. zone)
            count = count + 1
        end
    end

    if count == 0 then
        Core.PrintC(Core.COLOR.WARN, "Friends list is empty.")
        return
    end

    -- Also show what this player's locationName is
    local myDetail = Inspect.Unit.Detail("player")
    local myLoc    = myDetail and myDetail.locationName or "nil"
    Core.PrintC(Core.COLOR.DIM, "Your locationName = " .. myLoc)

    -- Now show who would be contacted
    local nearby = data.Comms.FindOnlineFriends()
    local contactColor = #nearby > 0 and Core.COLOR.SUCCESS or Core.COLOR.WARN
    Core.PrintC(contactColor, "Would contact (" .. #nearby .. "): " ..
        (#nearby > 0 and table.concat(nearby, ", ") or "nobody"))
end

-- --------------------------------------------------------
-- PrintDebug
-- --------------------------------------------------------

function UI.PrintDebug()
    Core.PrintC(Core.COLOR.DIM,
        Core.NAME .. " v" .. Core.VERSION ..
        " | Player: "  .. (Core.state.playerName or "?") ..
        " | Role: "    .. Roles.GetRole() ..
        " | Leader: "  .. (Core.state.leaderName or "none") ..
        " | Party: "   .. (Core.state.groupCount or 0)
    )

    if data.Follow then
        local f = data.Follow.GetDebugInfo()
        Core.PrintC(Core.COLOR.DIM,
            "Follow : active=" .. tostring(f.active) ..
            " traveling=" .. tostring(f.traveling) ..
            " target=" .. tostring(f.hasTarget) ..
            " seq=" .. tostring(f.lastSeq) ..
            " drops=" .. tostring(f.drops) ..
            " leadBcast=" .. tostring(data.Follow.leaderBroadcast))
    end

    if data.Assist then
        local a = data.Assist.GetDebugInfo()
        Core.PrintC(Core.COLOR.DIM,
            "Assist : leaderOn=" .. tostring(a.leaderOn) ..
            " followerOn=" .. tostring(a.followerOn) ..
            " lastKey=" .. tostring(a.lastKey))
    end

    if data.Comms then
        local outstanding = 0
        for _ in pairs(data.Comms._outstanding) do outstanding = outstanding + 1 end
        Core.PrintC(Core.COLOR.DIM,
            "Comms  : proto v" .. data.Comms.PROTO_VERSION ..
            " unacked=" .. outstanding ..
            " pending=" .. #data.Comms.GetPendingFollowers())
    end
end

-- --------------------------------------------------------
-- PrintStatus
-- --------------------------------------------------------

function UI.PrintStatus()
    Core.PrintC(Core.COLOR.PREFIX,   "--- MultiFollow Status ---")
    Core.PrintC(Core.COLOR.INFO,     "Character : " .. (Core.state.playerName or "?"))
    local role = Roles.GetRole()
    local roleColor = (role == "leader") and Core.COLOR.LEADER or
                      (role == "follower") and Core.COLOR.FOLLOWER or Core.COLOR.DIM
    Core.PrintC(roleColor,           "Role      : " .. role)
    Core.PrintC(Core.COLOR.INFO,     "Leader    : " .. (Core.state.leaderName or "(none)"))
    Core.PrintC(Core.COLOR.INFO,     "Party members: " .. (Core.state.groupCount or 0))

    if Core.state.groupCount > 0 and data.Group then
        for _, name in ipairs(data.Group.GetMemberNames()) do
            Core.PrintC(Core.COLOR.DIM, "  [party] " .. name)
        end
    end

    if Core.config.role == "leader" and data.Comms then
        local pending = data.Comms.GetPendingFollowers()
        if #pending > 0 then
            Core.PrintC(Core.COLOR.WARN, "Followers awaiting invite (" .. #pending .. "):")
            for _, name in ipairs(pending) do
                Core.PrintC(Core.COLOR.INVITE, "  /invite " .. name)
            end
        end
    end

    -- Session modes
    if data.Follow then
        local mode
        if Core.config.role == "leader" then
            mode = data.Follow.leaderBroadcast and "BROADCASTING positions" or "idle"
        else
            mode = data.Follow.IsActive() and "FOLLOWING leader" or "idle"
        end
        Core.PrintC(Core.COLOR.DIM, "Mode      : " .. mode)
    end

    if data.Assist then
        local a = data.Assist.GetDebugInfo()
        Core.PrintC(Core.COLOR.DIM,
            "Assist    : " .. (a.leaderOn and "broadcasting" or
                               (a.followerOn and "mirroring" or "off")))
    end
end
