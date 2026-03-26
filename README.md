# MultiFollow

`MultiFollow` is a lightweight **RIFT MMO** multibox helper built around a practical rule:

**let the addon coordinate readiness, but let the leader handle the actual `/invite`.**

That keeps party formation simple and reliable while still giving you a clean leader/follower workflow.

## Highlights

- Leader / follower role tracking per character
- Nearby friend discovery for your multibox characters
- Pre-party addon messaging for leader announce and follower ready signals
- Party membership tracking after invites go out
- Clear `/mf` status output for quick checks
- Designed around small multibox groups, especially 2-character setups

## Status

`MultiFollow` is in active prototyping.

Current focus:

- reliable multibox setup
- clean leader/follower handoff
- predictable manual invite workflow

Current non-goals:

- automatic party invites through an unverified Rift API
- trying to force pre-party messaging to any online friend anywhere

## Why Manual Invite Is The Default

For multiboxing, manual `/invite` is the cleanest and most dependable workflow.

Rift addon messaging before a party exists is more restrictive than normal in-party communication, so `MultiFollow` treats party formation like this:

- use addon messaging for discovery and readiness
- use normal `/invite` for the actual group invite
- use addon coordination after the party exists

That keeps the addon useful without depending on fragile pre-party automation.

## Workflow At A Glance

Example characters:

- leader: `Shadowkorn`
- follower: `Betatest`

Recommended flow:

1. Log both characters in.
2. On the leader, run `/mf lead`.
3. On the follower, run `/mf follow Shadowkorn` if needed.
4. On the leader, invite with `/invite Betatest`.
5. Run `/mf status` on the leader if you want to confirm readiness or current group state.

## Commands

| Command | What it does |
| --- | --- |
| `/mf lead` | Set this character as leader and announce to nearby friended followers. |
| `/mf follow` | Set this character as follower. |
| `/mf follow <leaderName>` | Set follower role, save the leader name, and send a ready signal immediately. |
| `/mf ready` | Re-send a ready signal to the saved leader. |
| `/mf scan` | Show which friended characters are currently being detected. |
| `/mf status` | Show role, leader, party count, and pending follower invites. |
| `/mf debug` | Print a compact debug/status line. |
| `/mf help` | Show command help. |

## Installation

1. Close Rift, or be ready to run `reloadui`.
2. Put the addon folder here:

```text
Documents\RIFT\Interface\AddOns\MultiFollow
```

3. Start Rift.
4. Run `reloadui` if the addon was added while the game was already open.

## Notes

- Your multibox characters should be on your friends list.
- Nearby detection is most reliable when the characters are physically close in the same area.
- Pre-party addon messaging can still be session-sensitive in fresh logins, so manual `/invite` remains the intended fallback.
- If the addon shows a follower as ready, the leader can just invite with the normal in-game command.

## Project Layout

- [`core.lua`](./core.lua) - shared state, constants, and config defaults
- [`roles.lua`](./roles.lua) - leader / follower role management
- [`comms.lua`](./comms.lua) - addon messaging and follower readiness tracking
- [`group.lua`](./group.lua) - party membership scanning
- [`ui.lua`](./ui.lua) - slash commands and console output
- [`main.lua`](./main.lua) - addon bootstrap and event wiring
- [`RiftAddon.toc`](./RiftAddon.toc) - Rift addon manifest

## Roadmap

- Improve nearby-visible follower detection so pre-party messaging is more consistent
- Add cleaner post-party follow / assist command handling
- Tighten the two-character setup flow for everyday multibox use
- Add screenshots / demo gifs to this README
