# Homelab

Self-hosted apps on a small set of machines at home, with encrypted off-site backups and a standby ready to take over.

## Nodes

**Node**:
A machine managed by this repo, such as a Raspberry Pi or the optional cloud VM.
_Avoid_: host, server, box, device

**Node name**:
The name a node has in the inventory, such as `rpi-home`. It identifies the node everywhere in this repo, including where its backups are kept.
_Avoid_: hostname (that is a different thing), inventory name

**Hostname**:
The name the node's operating system and Tailscale use, such as `merry`. It can change when a node is rebuilt, while the node name stays the same.
_Avoid_: node name, Tailscale name (same thing; say hostname)

**Primary**:
The node that normally runs the apps.
_Avoid_: main node, home node

**Standby**:
A node that runs only the base stack and can take over the apps from the primary.
_Avoid_: backup node (a backup is data, not a node), secondary, friend node

**Active node**:
The node currently running the apps. It is the primary until a failover makes it the standby.
_Avoid_: current node, live node

**Failover**:
Making the standby the active node, by restoring the active node's latest backup onto it and starting the apps there.
_Avoid_: promotion, switchover

## Stacks

**Stack**:
A named group of containers deployed together to a node: base, apps or cloud.
_Avoid_: service, project, deployment

**Base stack**:
The stack every Raspberry Pi node runs: reverse proxy, database and cache.

**Apps stack**:
The stack of user-facing apps, run only on the active node.

## Backups

**Backup set**:
One timestamped copy of a node's stacks, app data and database dumps, stored off-site under its node name.
_Avoid_: snapshot, backup (when the single copy is meant), archive

**With-media backup set**:
A backup set that also includes media files. It is kept apart from the normal backup sets and does not count toward retention.

**Retention**:
The rule deciding which backup sets are kept and which are deleted.
_Avoid_: rotation, cleanup, pruning policy

**Restore**:
Bringing a node's data back from a backup set onto a node, which may be a different node from the one that made it.
_Avoid_: recovery (recovery is the whole rebuild, of which restore is one step)

**Rebuild**:
Bringing a dead node back from a fresh operating system install to fully working, including a restore.
_Avoid_: reinstall, disaster recovery (as a step name)
