# Managed Clash YAML Subscriptions Design

## Goal

Extend the Clash YAML converter so URL input becomes a daede-managed,
refreshable airport subscription, while pasted YAML remains a static node
snapshot. dae and daed continue receiving compatible converted nodes and an
airport group because neither backend can natively consume Clash YAML.

## Product Model

The input source determines the third-step behavior:

- A fetched Clash YAML URL is a **managed subscription**. daede securely saves
  the source, imports every compatible node, and can refresh the airport later.
- Pasted Clash YAML is a **static snapshot**. daede imports only the nodes the
  user selected and does not retain the pasted YAML.

Managed subscriptions are represented as `node + group` in both dae and daed.
They must not be inserted into the backend's native `subscription` collection,
because that collection does not parse Clash YAML.

## Third-Step User Interface

After a URL is fetched and parsed, step three becomes `Save Managed
Subscription` and shows:

- Airport name.
- Target backend.
- Automatic update switch, disabled by default.
- Update interval presets: 24, 36, 48, and 72 hours.
- A custom interval in hours, limited to 1 through 720 hours.
- For daed, controls to save or replace its login credentials.
- A `Save and Sync Now` action.
- A note that every refresh imports all compatible nodes and ignores
  subscription-information pseudo-nodes and unsupported protocols.

After pasted YAML is parsed, step three becomes `Import Static Nodes` and
shows:

- Group name.
- Target backend.
- An action that imports only the currently selected compatible nodes.

Static snapshots retain the existing airport grouping and synchronized
replacement behavior but have no update schedule or saved source.

## Managed Subscription List

The top of the converter page contains a managed-subscription list. Each row
shows:

- Airport name and target backend.
- Automatic update state and interval.
- Last successful update time.
- Current managed-node count.
- Latest update result.
- Actions: `Update Now`, `Edit`, and `Delete`.

Delete offers two explicit choices:

1. Stop management and keep the current backend nodes and group.
2. Delete the managed subscription together with its owned nodes and group.

Nodes shared with another managed airport or another daed group are never
deleted globally.

## Configuration And Secrets

Non-secret state lives in `/etc/config/daede` as stable named or anonymous
`airport` sections:

```text
config airport
    option id 'airport_<stable-id>'
    option kind 'managed_url'
    option name 'Flower_SS'
    option backend 'daed'
    option user_agent 'auto'
    option auto_update '1'
    option interval_hours '24'
    option last_attempt '...'
    option last_success '...'
    option last_result 'ok'
    option last_error ''
    option group_id '<backend-group-id>'
    list node_id '<owned-node-id>'
```

Static snapshots use `kind 'static_yaml'` and do not receive scheduling fields.

Secrets live in `/etc/config/daede_secrets`, which is owned by root and has
mode `0600`:

```text
config source 'airport_<stable-id>'
    option url '<clash-yaml-url>'

config daed 'credentials'
    option username '<username>'
    option password '<password>'
```

The subscription URL is treated as a secret because it commonly contains an
account token. LuCI may show a masked host or source description but never
returns the full URL or password to ordinary page rendering. Passwords are
never displayed after saving.

One saved daed credential set is shared by all managed daed subscriptions.
Manual synchronization may use the saved credentials or replace them.

## Backend Synchronization Service

The current browser-only dae and daed synchronization logic moves into a
backend command that both LuCI and scheduled jobs call. The browser remains
responsible for previewing YAML and importing static snapshots. Managed URL
refreshes are performed entirely by the backend.

The backend command supports:

```text
sync <airport-id>          Fetch, convert, and synchronize one subscription.
sync-due                   Synchronize every overdue enabled subscription.
delete <airport-id> keep   Stop management and preserve backend objects.
delete <airport-id> purge  Remove safely owned backend objects and state.
```

Synchronization follows a stage-before-cutover rule:

1. Acquire a per-airport lock. If already locked, skip the duplicate run.
2. Read the secret URL, saved User-Agent, backend, and credentials.
3. Fetch the Clash YAML and parse all proxy entries.
4. Remove metadata pseudo-nodes and unsupported protocols.
5. Require at least one compatible node.
6. Stage or import the new nodes and make the airport group usable.
7. Only after successful cutover, remove stale safely owned nodes.
8. Persist new ownership, node count, timestamps, and result.

Any failure before cutover preserves the previous nodes and group. Cleanup
failure after cutover records a warning but keeps the new usable airport.

## dae Behavior

For dae, the service writes managed UCI `node` sections and one managed
`group` section, then invokes `gen-dae-config.sh generate`. It snapshots the
previous managed sections before changes. If generation or dae validation
fails, it restores the snapshot and regenerates the prior configuration.

The group source contains every managed node tag. Nodes and groups outside the
airport ownership record are not removed.

## daed Behavior

For daed, the service authenticates with the saved root-only credentials and
uses the GraphQL API to import nodes and maintain one group. New nodes are
added and the group is made usable before stale membership is removed.

Shared nodes remain globally available. A stale node is deleted only when it
is owned by this airport and is not referenced by another managed airport or
another daed group.

## Scheduling And Boot Recovery

A periodic cron entry runs `sync-due`. Each airport has an independent
interval:

- Presets: 24, 36, 48, or 72 hours.
- Custom value: 1 through 720 hours.
- Default: 24 hours.
- Automatic update is disabled by default.

The checker compares the current time with the last successful update. It does
not create one cron entry per airport.

During router startup, an init hook waits approximately two minutes and then
runs `sync-due`. This catches overdue subscriptions after the network has had
time to become usable. Per-airport locks prevent the boot job, cron, and
manual action from updating the same airport concurrently.

## Error Handling And Status

Failures retain the previous usable nodes and group. The managed-subscription
list displays a specific latest result:

- Fetch failure, including TLS and HTTP errors.
- YAML parse failure.
- No compatible nodes.
- daed authentication failure.
- Backend synchronization or validation failure.
- Successful synchronization with cleanup warning.

`last_attempt` and `last_error` change on failure. `last_success` changes only
after successful cutover. Repeated failures do not clear or rebuild the
existing airport.

## Migration

Existing airport records without `kind` remain static snapshots. Existing
nodes and groups are not modified during package upgrade.

The current URL-imported airports cannot become managed subscriptions
automatically because their secret source URL was intentionally not saved.
Users may fetch the URL again and select the existing airport to convert it
into a managed subscription.

## Verification

- Unit tests cover interval validation, due-time calculation, secret redaction,
  source-kind behavior, metadata filtering, and lock handling.
- Backend tests cover successful first sync, refresh replacement, fetch and
  parse failures, dae rollback, daed authentication failure, shared-node
  preservation, keep deletion, and purge deletion.
- LuCI tests cover dynamic third-step content, managed-subscription editing,
  status rendering, delete choices, and Chinese translations.
- Device 252 verification covers manual refresh, cron due refresh, the
  two-minute boot recovery path, dae and daed synchronization, and retained
  old nodes after an induced failure.
- Desktop and 375-pixel mobile layouts are verified under Argon and Bootstrap
  light and dark themes.

## Non-Goals

- Teaching dae or daed to parse Clash YAML natively.
- Persisting pasted YAML.
- Remembering a selected-node subset for managed URL subscriptions.
- Importing Clash proxy groups, rules, DNS settings, or routing settings.
- Globally deleting backend objects not owned by daede.
