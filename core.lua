-- ============================================================
-- MultiFollow | core.lua
-- Purpose : Central state, constants, and config.
--           All other modules read from Core; none write to
--           each other directly.
-- ============================================================

local toc, data = ...

-- Create the global addon table, keyed by toc identifier.
-- Every file gets the same 'data' table via varargs, so modules
-- can attach to it. We also expose it as a global for convenience.
MultiFollow = data
MultiFollow.Core = MultiFollow.Core or {}

local Core = MultiFollow.Core

-- --------------------------------------------------------
-- Constants  (sourced from toc where possible)
-- --------------------------------------------------------

-- toc.identifier is confirmed lowercase in working addons (Gadgets pattern).
-- Version and Name field casing is inconsistent across Rift's API
-- (RiftMeter reads Info.toc.Version with capital V via a nested sub-table).
-- Hardcoding these is the safest approach — update here when bumping versions.
Core.IDENTIFIER     = toc.identifier
Core.VERSION        = "0.1.0"
Core.NAME           = "MultiFollow"
Core.MSG_IDENTIFIER = "MF:CMD"               -- 3+ chars required by API
Core.MAX_GROUP      = 5                       -- 1 leader + 4 followers

-- --------------------------------------------------------
-- Runtime state  (non-persistent; resets each session)
-- --------------------------------------------------------

Core.state = {
    initialized = false,
    playerName  = nil,
    leaderName  = nil,       -- name of the current leader (set on all chars)
    group       = {},        -- [specifier] = { name, unitId } e.g. group01..group04
    groupCount  = 0,         -- number of party members (not counting self)
}

-- --------------------------------------------------------
-- Saved-variable defaults
-- MultiFollowDB is declared in toc as account-scoped.
-- main.lua merges these after SavedVariables.Load.End fires.
-- --------------------------------------------------------

Core.defaults = {
    role        = "unassigned",  -- "leader" | "follower" | "unassigned"
    leaderName  = nil,           -- persisted so followers remember their leader
    version     = Core.VERSION,
}

-- --------------------------------------------------------
-- Live config  (merged from defaults + MultiFollowDB)
-- --------------------------------------------------------

Core.config = {}

-- --------------------------------------------------------
-- Color palette
-- Used by Core.Print / Core.PrintC for HTML-colored output.
-- Console supports: <font color="#rrggbb">, <u>, <a lua="...">
-- --------------------------------------------------------

Core.COLOR = {
    PREFIX   = "#FFD100",  -- gold   — [MultiFollow] tag
    INFO     = "#FFFFFF",  -- white  — general info
    LEADER   = "#00CCFF",  -- cyan   — leader role messages
    FOLLOWER = "#88FF88",  -- green  — follower role messages
    INVITE   = "#FFFF44",  -- yellow — /invite commands
    SUCCESS  = "#44FF88",  -- bright green — all-ready confirmation
    WARN     = "#FF9900",  -- orange — warnings / cap reached
    ERROR    = "#FF4444",  -- red    — errors
    DIM      = "#AAAAAA",  -- gray   — debug / low-priority info
}

-- --------------------------------------------------------
-- Core.Print  — plain white body text, gold prefix
-- Core.PrintC — colored body text
-- Verified 4-param signature from LLM_RIFT_API_v2_audited:
--   Command.Console.Display(console, suppressPrefix, text, html)
-- --------------------------------------------------------

local function _prefix()
    return '<font color="' .. Core.COLOR.PREFIX .. '">[' .. Core.NAME .. ']</font> '
end

function Core.Print(msg)
    Command.Console.Display("general", true,
        _prefix() .. '<font color="' .. Core.COLOR.INFO .. '">' .. tostring(msg) .. '</font>',
        true)
end

function Core.PrintC(color, msg)
    Command.Console.Display("general", true,
        _prefix() .. '<font color="' .. color .. '">' .. tostring(msg) .. '</font>',
        true)
end

-- --------------------------------------------------------
-- Core.ApplyDefaults
-- Shallow-merges defaults into target (first-run safety).
-- --------------------------------------------------------

function Core.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = v
        end
    end
end
