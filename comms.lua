-- ============================================================
-- MultiFollow | comms.lua
-- Purpose : All addon messaging. Fully silent — no chat output.
--
-- PRE-PARTY HANDSHAKE  : Command.Message.Send (direct, reliable)
--   Sends directly to a named player.
--   API restriction: target must be nearby, in your guild,
--   in your party/raid, OR have sent you a message/tell this
--   session. Works for guild members reliably.
--
-- IN-PARTY COMMANDS    : Command.Message.Broadcast("party", ...)
--   Once grouped, party broadcast is used for follow/assist/stop.
--
-- PAYLOAD FORMAT
--   "MF:LEAD:<name>"   — leader→follower: I am the leader
--   "MF:FOLL:<name>"   — follower→leader: I am ready, invite me
--   "MF:CMD:<command>" — leader→party:   follow / assist / stop
--
-- Accept types (Command.Message.Accept valid types):
--   "send"   — direct messages via Command.Message.Send
--   "guild"  — guild broadcast (kept for future use)
--   "party"  — party broadcast (in-group commands)
-- ============================================================
-- Verified API (LLM_RIFT_API_v2_audited):
--   Command.Message.Send(target, identifier, data, callback)
--   Command.Message.Accept(type, identifier)
--     Valid types: "tell","channel","guild","officer","party",
--                  "raid","say","yell","send"
--   Event.Message.Receive(from, type, channel, identifier, data)
--     type = "send" for direct messages
-- ============================================================

local toc, data = ...

local Core  = data.Core
local Comms = {}
data.Comms  = Comms
MultiFollow.Comms = Comms

Comms._pendingFollowers = {}

-- ============================================================
-- Init
-- Accept "say" (pre-party proximity broadcast), "party"
-- (in-group commands), and "send"/"guild" as fallbacks.
-- "say" broadcast is silent, has no session or guild
-- requirement — just requires proximity, which is always
-- true for multiboxing characters.
-- ============================================================

function Comms.Init()
    Command.Message.Accept("say",   Core.MSG_IDENTIFIER)
    Command.Message.Accept("send",  Core.MSG_IDENTIFIER)
    Command.Message.Accept("guild", Core.MSG_IDENTIFIER)
    Command.Message.Accept("party", Core.MSG_IDENTIFIER)

    Command.Event.Attach(
        Event.Message.Receive,
        Comms._OnReceive,
        Core.IDENTIFIER .. "_MsgReceive"
    )
end

-- ============================================================
-- FindOnlineFriends
-- Returns a list of online friend names.
-- Handles both {[name]=value} and {"name1","name2"} formats
-- defensively since the key format is undocumented.
-- ============================================================

function Comms.FindOnlineFriends()
    local friends = Inspect.Social.Friend.List()
    if not friends then return {} end

    local online = {}

    for k, v in pairs(friends) do
        local friendName = (type(k) == "string") and k or
                           (type(v) == "string") and v or nil
        if friendName then
            local detail = Inspect.Social.Friend.Detail(friendName)
            if detail then
                local isOnline = (detail.status == "online" or detail.status == "afk")
                if isOnline then
                    table.insert(online, detail.name or friendName)
                end
            end
        end
    end

    return online
end

-- ============================================================
-- SendLeaderAnnounce
-- Broadcasts MF:LEAD via "say" channel — reaches all nearby
-- players running MultiFollow with no session or guild
-- requirement. Completely silent (never appears in chat).
-- ============================================================

function Comms.SendLeaderAnnounce()
    local myName = Core.state.playerName or ""
    Comms._pendingFollowers = {}

    Command.Message.Broadcast(
        "say",
        nil,
        Core.MSG_IDENTIFIER,
        "MF:LEAD:" .. myName
    )

    local online = Comms.FindOnlineFriends()
    local expect = math.min(#online, Core.MAX_GROUP - 1)
    Core.PrintC(Core.COLOR.LEADER,
        "Leader announce broadcast (say). Expecting up to " .. expect .. " reply(s)...")
end

-- ============================================================
-- SendFollowerReady
-- Follower broadcasts MF:FOLL via "say" channel — same
-- proximity-based silent broadcast back to the leader.
-- ============================================================

function Comms.SendFollowerReady()
    local myName = Core.state.playerName or ""

    Command.Message.Broadcast(
        "say",
        nil,
        Core.MSG_IDENTIFIER,
        "MF:FOLL:" .. myName
    )
end

-- ============================================================
-- SendPartyCommand  (Pass 3+)
-- Broadcasts a command to all party members.
-- ============================================================

function Comms.SendPartyCommand(cmd)
    Command.Message.Broadcast(
        "party",
        nil,
        Core.MSG_IDENTIFIER,
        "MF:CMD:" .. tostring(cmd)
    )
end

-- ============================================================
-- _OnReceive
-- Routes inbound messages by type and payload prefix.
-- ============================================================

function Comms._OnReceive(handle, from, msgType, channel, identifier, msgData)
    if identifier ~= Core.MSG_IDENTIFIER then return end
    if not msgData then return end

    -- Leader announce received by followers (direct send)
    local leaderName = msgData:match("^MF:LEAD:(.+)$")
    if leaderName then
        if leaderName ~= Core.state.playerName and data.Roles then
            data.Roles.OnLeaderAnnounce(leaderName)
        end
        return
    end

    -- Follower ready reply received by leader (direct send)
    local followerName = msgData:match("^MF:FOLL:(.+)$")
    if followerName then
        if Core.config.role == "leader" and followerName ~= Core.state.playerName then
            Comms._RegisterFollower(followerName)
        end
        return
    end

    -- In-party commands (Pass 3+)
    local cmd = msgData:match("^MF:CMD:(.+)$")
    if cmd then
        -- TODO: dispatch to Roles in later passes
        return
    end
end

-- ============================================================
-- _RegisterFollower
-- Tracks followers as they reply to the leader.
-- Prints the /invite command for each new follower.
-- ============================================================

function Comms._RegisterFollower(name)
    -- Duplicate check first
    for _, n in ipairs(Comms._pendingFollowers) do
        if n == name then return end
    end

    local max = Core.MAX_GROUP - 1

    if #Comms._pendingFollowers >= max then
        Core.PrintC(Core.COLOR.WARN, "Follower cap reached (" .. max .. "). Ignoring: " .. name)
        return
    end

    table.insert(Comms._pendingFollowers, name)
    local count = #Comms._pendingFollowers

    Core.PrintC(Core.COLOR.FOLLOWER, "Follower ready [" .. count .. "/" .. max .. "]: " .. name)
    Core.PrintC(Core.COLOR.INVITE,   "  --> /invite " .. name)

    if count >= max then
        Core.PrintC(Core.COLOR.SUCCESS, "All followers ready. Invite them and multiboxing is armed.")
    end
end

-- ============================================================
-- GetPendingFollowers
-- ============================================================

function Comms.GetPendingFollowers()
    return Comms._pendingFollowers
end
