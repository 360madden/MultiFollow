# Workflow

## Purpose

Defines the operational workflow for MultiFollow based on current implementation.

---

## Standard Workflow

### Step 1 - Start clients
Launch all intended characters.

### Step 2 - Establish leader
On leader:

```
/mf lead
```

### Step 3 - Establish followers
On followers:

```
/mf follow <LeaderName>
```

### Step 4 - Send readiness

```
/mf ready
```

### Step 5 - Manual invite

```
/invite <FollowerName>
```

### Step 6 - Verify

```
/mf status
```

---

## Key Design Decision

Manual invite is intentional.

The addon handles coordination, not automation.

---

## Recovery

Followers can:
- reload UI
- re-send `/mf ready`
- be re-invited

---

## Diagnostics

- `/mf scan`
- `/mf status`
- `/mf debug`

---

## Boundaries

Not included:
- movement
- targeting
- automation

These belong to external systems.
