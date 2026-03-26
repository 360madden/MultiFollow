# MultiFollow

`MultiFollow` is a small multibox helper addon for **RIFT MMO**.

It is built around a simple leader/follower model:

- the leader announces itself with addon messaging
- follower characters can recognize that leader and mark themselves ready
- the leader manually invites followers with the normal in-game `/invite` command

The addon is intentionally conservative during party formation. For a two-character setup, the cleanest workflow is still:

1. Start the leader with `/mf lead`
2. Start the follower with `/mf follow <leaderName>` if needed
3. Invite manually with `/invite <followerName>`

After the party is formed, the addon can be extended for leader-driven follow / assist behavior.

## Current Status

This project is focused on reliable multibox setup for a small party.

What it does now:

- tracks a leader / follower role per character
- scans nearby friended characters
- sends pre-party addon messages between characters
- tracks follower readiness on the leader
- prints pending manual invite targets
- watches party membership changes

What it does not currently do:

- auto-invite through a Rift party API
- guarantee pre-party messaging to any online friend anywhere

## Why Manual Invite Is Preferred

For multiboxing, manual `/invite` is the most reliable option.

Rift addon messaging before a party exists is more restrictive than normal party communication. In practice, that means party formation is best kept simple:

- use addon messaging for discovery / readiness
- use `/invite` for the actual group invite
- use the addon for party behavior after the group exists

## Commands

- `/mf lead`
  Set this character as leader and announce to nearby friended followers.

- `/mf follow`
  Set this character as follower.

- `/mf follow <leaderName>`
  Set this character as follower, save the leader name, and immediately send a ready signal.

- `/mf ready`
  Re-send a ready signal to the saved leader.

- `/mf scan`
  Show which nearby friended characters the addon currently detects.

- `/mf status`
  Show current role, leader, group count, and pending follower invites.

- `/mf debug`
  Print a compact debug/status line.

- `/mf help`
  Show command help.

## Installation

1. Close Rift, or be ready to run `reloadui`.
2. Place the addon folder here:

```text
Documents\RIFT\Interface\AddOns\MultiFollow
```

3. Start Rift.
4. Run `reloadui` if needed.

## Recommended Two-Character Workflow

Example:

- leader: `Shadowkorn`
- follower: `Betatest`

Suggested flow:

1. Log both characters in.
2. On the leader, run `/mf lead`.
3. On the follower, run `/mf follow Shadowkorn` if it has not already learned the leader.
4. On the leader, invite with `/invite Betatest`.
5. Use `/mf status` on the leader if you want to confirm follower readiness.

## Notes

- The addon currently expects your multibox characters to be on your friends list.
- Nearby detection is more reliable when the characters are physically close in the same area.
- If pre-party addon messaging is inconsistent in a fresh session, manual `/invite` is still the intended fallback.

## Files

- [`core.lua`](./core.lua) - shared state, constants, config defaults
- [`roles.lua`](./roles.lua) - leader / follower role handling
- [`comms.lua`](./comms.lua) - addon messaging and follower readiness tracking
- [`group.lua`](./group.lua) - party membership scanning
- [`ui.lua`](./ui.lua) - slash commands and status output
- [`main.lua`](./main.lua) - addon bootstrap and event wiring
- [`RiftAddon.toc`](./RiftAddon.toc) - Rift addon manifest
