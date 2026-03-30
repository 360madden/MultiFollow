# Architecture

## Purpose

This document describes the current technical architecture of MultiFollow and separates **implemented behavior** from **planned behavior**.

---

## High-Level Model

MultiFollow is a **single-addon, multi-client coordination layer**.

Each RIFT client instance runs the same addon code in its own sandbox. There is no direct shared state between instances. Coordination therefore depends on addon messaging plus per-client saved variables.

### Design principle

Each client knows:
- its own runtime role
- its own saved leader association
- its own current party state

No client directly reads another client's memory or UI state.

---

## Runtime Components

### Core
File: `core.lua`

Responsibilities:
- constants
- version and identifier
- runtime state table
- defaults for saved variables
- console print helpers

### Roles
File: `roles.lua`

Responsibilities:
- role transitions
- save/load role and leader name
- follower startup reminder
- future command hooks such as follow/assist

### Comms
File: `comms.lua`

Responsibilities:
- accept addon-message channels
- send leader announce
- send follower ready
- track pending followers on the leader
- route inbound messages by payload prefix

### Group
File: `group.lua`

Responsibilities:
- rebuild current party registry from `group01`-`group04`
- count party members
- detect join/leave availability events
- expose simple member-name list for status display

### UI
File: `ui.lua`

Responsibilities:
- register `/mf`
- parse commands
- display help, debug, scan, and status output

### Main
File: `main.lua`

Responsibilities:
- saved variable load merge
- player-name discovery
- dependency-order initialization
- event wiring only

---

## Current Communication Flow

### Pre-party
1. Leader becomes leader.
2. Leader broadcasts `MF:LEAD:<leaderName>`.
3. Followers receive the announce.
4. Followers become followers and send `MF:FOLL:<followerName>`.
5. Leader records pending followers.
6. User sends standard `/invite` commands.

### Post-party
1. Group membership is tracked by availability events.
2. Party command support is planned but not fully implemented.

---

## Current State Boundaries

### Persistent state
Stored in `MultiFollowDB`:
- role
- leader name
- version

### Runtime-only state
Stored in `Core.state`:
- initialized flag
- current player name
- current leader name
- current party registry
- current party count

This split is appropriate for an addon of this size.

---

## Architectural Strengths

- narrow scope
- clean separation of modules
- practical manual-invite checkpoint
- no attempt to fake unsupported API powers

---

## Architectural Weaknesses

- comments and implementation are not perfectly aligned
- protocol naming is not yet clean
- no message assurance layer exists
- post-party command handling is still unfinished

---

## Recommended Strategic Position

MultiFollow should remain:
- compact
- addon-scoped
- coordination-focused

It should not try to become a full external-control or telemetry platform inside Lua.
