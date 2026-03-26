-- ============================================================
-- MultiFollow | main.lua
-- Purpose : Bootstrap and wiring only.
--           Attaches all lifecycle and availability events.
--           No logic lives here - delegates to modules.
-- ============================================================

local toc, data = ...
local Core = data.Core

-- --------------------------------------------------------
-- 1. Saved-variable load
-- --------------------------------------------------------

local function OnSavedVarsLoaded(handle, identifier)
    if identifier ~= toc.identifier then return end

    if type(MultiFollowDB) ~= "table" then
        MultiFollowDB = {}
    end

    Core.ApplyDefaults(MultiFollowDB, Core.defaults)
    Core.config.role       = MultiFollowDB.role
    Core.config.leaderName = MultiFollowDB.leaderName
    Core.config.version    = MultiFollowDB.version

    -- Restore leader name into runtime state so it survives reload
    Core.state.leaderName = MultiFollowDB.leaderName
end

Command.Event.Attach(
    Event.Addon.SavedVariables.Load.End,
    OnSavedVarsLoaded,
    toc.identifier .. "_SVLoad"
)

-- --------------------------------------------------------
-- 2. Addon load-end - main init
-- --------------------------------------------------------

local function OnLoadEnd(handle, identifier)
    if identifier ~= toc.identifier then return end

    -- Populate player name
    local detail = Inspect.Unit.Detail("player")
    if detail and detail.name then
        Core.state.playerName = detail.name
    end

    -- Init sub-modules in dependency order
    data.Comms.Init()
    data.UI.Init()

    -- Initial group scan (in case already in a party on reload)
    data.Group.Scan()

    Core.state.initialized = true

    Core.PrintC(Core.COLOR.PREFIX,
        "v" .. Core.VERSION .. " loaded | Role: " .. (Core.config.role or "unassigned"))

    if data.Roles and data.Roles.MaybePrintStartupReminder then
        data.Roles.MaybePrintStartupReminder()
    end
end

Command.Event.Attach(
    Event.Addon.Load.End,
    OnLoadEnd,
    toc.identifier .. "_LoadEnd"
)

-- --------------------------------------------------------
-- 3. Party member availability events
--    Delegate straight to Group module.
-- --------------------------------------------------------

Command.Event.Attach(
    Event.Unit.Availability.Full,
    function(handle, units) data.Group.OnAvailabilityFull(handle, units) end,
    toc.identifier .. "_AvailFull"
)

Command.Event.Attach(
    Event.Unit.Availability.None,
    function(handle, units) data.Group.OnAvailabilityNone(handle, units) end,
    toc.identifier .. "_AvailNone"
)
