-- ============================================================
-- MultiFollow | comms.lua
-- Purpose : All addon messaging. Fully silent - no chat output.
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
-- PAYLOAD FORMAT  (protocol v2)
--   "MF:LEAD:<seq>:<name>"        - leader->nearby: I am the leader
--   "MF:FOLL:<seq>:<name>"        - follower->leader: ready, invite me
--   "MF:ACK:<seq>:<id>"           - ack of any seq'd message
--   "MF:CMD:<command>"            - leader->party: follow / assist / stop / positions
--   "MF:POS:<seq>:<x>:<y>:<z>:<instance>"  - leader->party: my coords
--   "MF:TGT:<seq>:<hp>:<name>"    - leader->party: my target (assist)
--   "MF:BYE:<name>"               - either side: leaving the setup
--
-- RELIABILITY
--   Handshake messages (LEAD/FOLL) are re-sent on a timer until
--   acknowledged with MF:ACK. Say-channel broadcasts have no
--   delivery guarantee, so this assurance layer is required for
--   consistent formation.
--
-- Accept types (Command.Message.Accept valid types):
--   "send"   - direct messages via Command.Message.Send
--   "guild"  - guild broadcast (kept for future use)
--   "party"  - party broadcast (in-group commands)
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

-- Reliability-layer state
Comms.PROTO_VERSION  = 2
Comms.RETRY_MS       = 1500     -- resend interval for unacked handshake msgs
Comms.MAX_RETRIES    = 8        -- then give up (target likely not listening)
Comms._seq           = 0        -- local message sequence counter
Comms._outstanding   = {}       -- [msgId] = { payload, retries, sentAt }
Comms._seen          = {}       -- [msgId] = os.clock()  (dedupe window)
Comms._retryHandle   = nil

local function _nextSeq()
    Comms._seq = Comms._seq + 1
    return Comms._seq
end

local function _msgId(name, seq)
    return tostring(name) .. ":" .. tostring(seq)
end

-- ============================================================
-- Init
-- Accept "say" (pre-party proximity broadcast), "party"
-- (in-group commands), and "send"/"guild" as fallbacks.
-- "say" broadcast is silent, has no session or guild
-- requirement - just requires proximity, which is always
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
-- Assurance layer: sendHandshake / retry / ack
-- All handshake traffic (LEAD/FOLL) goes through here so a
-- lost say-broadcast is automatically re-sent.
-- Timing source: Event.Game.Tick (1 Hz), attached by main.lua
-- calling Comms.OnGameTick().
-- ============================================================

function Comms.OnGameTick()
    -- Retry unacked handshake messages every tick.
    for msgId, entry in pairs(Comms._outstanding) do
        entry.retries = entry.retries + 1
        if entry.retries >= Comms.MAX_RETRIES then
            Comms._outstanding[msgId] = nil
            Comms._OnHandshakeTimeout(msgId, entry)
        else
            Command.Message.Broadcast("say", nil, Core.MSG_IDENTIFIER, entry.payload)
        end
    end

    -- Prune dedupe cache older than 60s (os.clock ~ uptime seconds).
    local now = os.clock()
    for id, t in pairs(Comms._seen) do
        if now - t > 60 then Comms._seen[id] = nil end
    end
end

function Comms._SendHandshake(payloadKind, name)
    local seq     = _nextSeq()
    local msgId   = _msgId(name, seq)
    local payload = "MF:" .. payloadKind .. ":" .. seq .. ":" .. name

    Comms._BroadcastReliable(payload, msgId)
end

-- Broadcast on "say" now, register for retry until acked.
function Comms._BroadcastReliable(payload, msgId)
    Command.Message.Broadcast("say", nil, Core.MSG_IDENTIFIER, payload)

    Comms._outstanding[msgId] = {
        payload = payload,
        kind    = payload:match("^MF:(%a+)"),
        retries = 0,
    }
end

function Comms._AckMessage(msgId)
    local seqPart = tostring(msgId):match(":(%d+)$")
    Command.Message.Broadcast("say", nil, Core.MSG_IDENTIFIER,
        "MF:ACK:" .. (seqPart or "0") .. ":" .. msgId)
end

function Comms._OnHandshakeTimeout(msgId, entry)
    -- Only surface this on the leader side waiting for follower ready.
    if entry.kind == "FOLL" and Core.config.role == "leader" then
        local name = tostring(msgId):match("^([^:]+)")
        Core.PrintC(Core.COLOR.WARN,
            "No acknowledgement from " .. name ..
            " after " .. Comms.MAX_RETRIES .. " attempts. " ..
            "Is MultiFollow loaded on that character?")
    end
end

function Comms._MarkSeen(msgId)
    if Comms._seen[msgId] then return true end  -- duplicate
    Comms._seen[msgId] = os.clock()
    return false
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
-- Broadcasts MF:LEAD via "say" channel - reaches all nearby
-- players running MultiFollow with no session or guild
-- requirement. Completely silent (never appears in chat).
-- Retransmitted until acknowledged (assurance layer).
-- ============================================================

function Comms.SendLeaderAnnounce()
    local myName = Core.state.playerName or ""
    Comms._pendingFollowers = {}

    Comms._SendHandshake("LEAD", myName)

    local online = Comms.FindOnlineFriends()
    local expect = math.min(#online, Core.MAX_GROUP - 1)
    Core.PrintC(Core.COLOR.LEADER,
        "Leader announce broadcast (say, retrying until acked). Expecting up to "
        .. expect .. " reply(s)...")
end

-- ============================================================
-- SendFollowerReady
-- Follower broadcasts MF:FOLL via "say" channel - same
-- proximity-based silent broadcast back to the leader.
-- Retransmitted until the leader acknowledges.
-- ============================================================

function Comms.SendFollowerReady()
    local myName = Core.state.playerName or ""
    Comms._SendHandshake("FOLL", myName)
end

-- ============================================================
-- SendBye
-- Announces that this character is leaving the setup so the
-- other side can drop stale pending entries.
-- ============================================================

function Comms.SendBye()
    local myName = Core.state.playerName or ""
    Command.Message.Broadcast(
        "say", nil, Core.MSG_IDENTIFIER, "MF:BYE:" .. myName)
end

-- ============================================================
-- SendPartyCommand  (in-group control)
-- Broadcasts a command to all party members over the party
-- addon channel.
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
-- SendPosition / SendTargetUpdate
-- High-frequency telemetry uses plain party broadcasts (no ack;
-- freshness matters more than delivery, and updates repeat).
-- ============================================================

function Comms.SendPosition(x, y, z, instance)
    local seq = _nextSeq()
    Command.Message.Broadcast(
        "party", nil, Core.MSG_IDENTIFIER,
        ("MF:POS:%d:%.1f:%.1f:%.1f:%s"):format(seq, x, y or 0, z, tostring(instance or ""))
    )
end

function Comms.SendTargetUpdate(info)
    if not info then
        Command.Message.Broadcast(
            "party", nil, Core.MSG_IDENTIFIER, "MF:TGT:0:-1:__none__")
        return
    end
    local seq = _nextSeq()
    -- Sanitize name: strip colons which would break field parsing.
    local name = tostring(info.name or ""):gsub(":", "-")
    Command.Message.Broadcast(
        "party", nil, Core.MSG_IDENTIFIER,
        "MF:TGT:" .. seq .. ":" .. tonumber(info.hp or -1) .. ":" .. name
    )
end

-- ============================================================
-- _OnReceive
-- Routes inbound messages by payload prefix (protocol v2).
-- Dedupes seq'd handshake traffic; dispatches in-party
-- commands and telemetry to the owning modules.
-- ============================================================

function Comms._OnReceive(handle, from, msgType, channel, identifier, msgData)
    if identifier ~= Core.MSG_IDENTIFIER then return end
    if not msgData then return end
    local myName = Core.state.playerName or ""

    -- ---- ACK (assurance layer) --------------------------------
    local ackId = msgData:match("^MF:ACK:%d*:?([^%s]*)$")
    if ackId and ackId ~= "" then
        Comms._outstanding[ackId] = nil
        return
    end

    -- ---- Leader announce: MF:LEAD:<seq>:<name> ---------------
    local seq, leaderName = msgData:match("^MF:LEAD:(%d+):(.+)$")
    if leaderName then
        if string.lower(leaderName) == string.lower(myName) then return end
        local msgId = leaderName .. ":" .. seq
        Comms._AckMessage(msgId)
        if Comms._MarkSeen(msgId) then return end   -- duplicate retry
        if data.Roles then
            data.Roles.OnLeaderAnnounce(leaderName)
        end
        return
    end

    -- ---- Follower ready: MF:FOLL:<seq>:<name> ----------------
    local fSeq, followerName = msgData:match("^MF:FOLL:(%d+):(.+)$")
    if followerName then
        if string.lower(followerName) == string.lower(myName) then return end
        local msgId = followerName .. ":" .. fSeq
        Comms._AckMessage(msgId)
        if Comms._MarkSeen(msgId) then return end
        if Core.config.role == "leader" and data.Roles then
            data.Roles.OnFollowerReady(followerName)
        end
        return
    end

    -- ---- Bye --------------------------------------------------
    local byeName = msgData:match("^MF:BYE:(.+)$")
    if byeName then
        Comms._UnregisterPending(byeName)
        return
    end

    -- ---- In-party commands: MF:CMD:<cmd> ----------------------
    local cmd = msgData:match("^MF:CMD:(.+)$")
    if cmd then
        Comms._DispatchCommand(cmd)
        return
    end

    -- ---- Position telemetry: MF:POS:<seq>:<x>:<y>:<z>:<inst> --
    local pSeq, px, py, pz, pInst =
        msgData:match("^MF:POS:(%d+):([%-%d%.]+):([%-%d%.]+):([%-%d%.]+):(.*)$")
    if pSeq then
        if Core.config.role ~= "leader" and data.Follow then
            data.Follow.OnLeaderPosition(
                tonumber(px), tonumber(py), tonumber(pz),
                (pInst ~= "" and pInst) or nil, tonumber(pSeq))
        end
        return
    end

    -- ---- Target telemetry: MF:TGT:<seq>:<hp>:<name> -----------
    local tSeq, tHp, tName = msgData:match("^MF:TGT:(%d+):(%-?%d+):(.+)$")
    if tSeq then
        if data.Assist then
            local info = nil
            if tName ~= "__none__" then
                info = { name = tName, hp = tonumber(tHp) }
            end
            data.Assist.OnTargetBroadcast(info)
        end
        return
    end
end

-- ============================================================
-- _DispatchCommand
-- MF:CMD payloads from the leader. Followers act; leaders
-- ignore their own echoes.
-- ============================================================

function Comms._DispatchCommand(cmd)
    if cmd == "follow-on" then
        if Core.config.role ~= "leader" and data.Follow then
            data.Follow.Start(true)
            Core.PrintC(Core.COLOR.FOLLOWER, "Follow mode enabled by leader.")
        end
    elseif cmd == "follow-off" or cmd == "stop" then
        if Core.config.role ~= "leader" and data.Follow then
            data.Follow.Stop(true)
            Core.PrintC(Core.COLOR.WARN, "Follow mode disabled by leader.")
        end
    elseif cmd == "assist-on" then
        if Core.config.role ~= "leader" and data.Assist then
            data.Assist.FollowerSet(true)
        end
    elseif cmd == "assist-off" then
        if Core.config.role ~= "leader" and data.Assist then
            data.Assist.FollowerSet(false)
        end
    elseif cmd == "status-request" then
        -- Leader asked followers to report readiness back.
        if Core.config.role ~= "leader" then
            Comms.SendFollowerReady()
        end
    end
end

-- ============================================================
-- _UnregisterPending  (private)
-- Remove a name from the pending-followers list (e.g. BYE).
-- ============================================================

function Comms._UnregisterPending(name)
    for i, n in ipairs(Comms._pendingFollowers) do
        if n == name then
            table.remove(Comms._pendingFollowers, i)
            Core.PrintC(Core.COLOR.DIM, "Follower withdrew: " .. name)
            return
        end
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

-- ============================================================
-- Roles.OnFollowerReady -> Comms._RegisterFollower is the
-- registration path (see roles.lua).
-- ============================================================

function Comms.GetPendingFollowers()
    return Comms._pendingFollowers
end

-- ============================================================
-- ClearPending
-- Leader calls this on /mf stop or when leaving setup.
-- Sends BYE for each still-uninvited follower? No - BYE is
-- sent by the withdrawing side; here we just drop our list.
-- ============================================================

function Comms.ClearPending()
    Comms._pendingFollowers = {}
end
