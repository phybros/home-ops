# CNPG databases with backups

Include this component in an application's Flux `ks.yaml` instead of maintaining
an app-specific `postgres.yaml`. It creates one `${APP}-postgres` cluster, its
Barman `ObjectStore`, backup credentials, and a daily `ScheduledBackup`.

```yaml
spec:
  targetNamespace: &namespace default
  components:
    - ../../../../components/cnpg
  dependsOn:
    - name: barman-cloud
      namespace: cnpg-system
    - name: rook-ceph-cluster
      namespace: rook-ceph
  postBuild:
    substitute:
      APP: example
      CNPG_NAMESPACE: *namespace
      CNPG_DATABASE: example
      CNPG_OWNER: example
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
```

`CNPG_NAMESPACE` must match `targetNamespace`; it separates backup archives by
namespace. Database and owner are explicit so migrating an existing application
does not accidentally change either. Connection names follow CNPG's conventions:
`${APP}-postgres-rw` for writes and `${APP}-postgres-app` for application credentials.

## Defaults and overrides

Set these optional variables in `postBuild.substitute` to override the defaults:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CNPG_INSTANCES` | `3` | PostgreSQL instance count; quote the override in `ks.yaml` |
| `CNPG_POSTGRES_VERSION` | `18` | Tag of `ghcr.io/cloudnative-pg/postgresql` |
| `CNPG_STORAGE_CLASS` | `ceph-block` | Database storage class |
| `CNPG_STORAGE_SIZE` | `1Gi` | Storage per instance |
| `CNPG_BACKUP_SCHEDULE` | `0 0 8 * * *` | Daily at 08:00 UTC; six cron fields, including seconds |
| `CNPG_BACKUP_RETENTION` | `7d` | Barman recovery window, not an exact backup count |
| `CNPG_BACKUP_COMPRESSION` | `gzip` | Base backup compression |
| `CNPG_WAL_COMPRESSION` | `gzip` | Transaction log compression |
| `CNPG_SERVER_NAME` | `${APP}-postgres` | Archive name backups are written under; only changed when recovering |

The first base backup is requested immediately when the schedule is created.
WAL archiving runs continuously because Barman's online backups require it, even
when only daily recovery points are needed.

The encrypted `cluster-secrets` supplies `SECRET_CNPG_BACKUP_PATH`, an S3 URL
separate from the Restic repositories. CNPG uses the existing
`SECRET_RESTIC_AWS_ACCESS_KEY_ID` and `SECRET_RESTIC_AWS_SECRET_ACCESS_KEY`.
Those credentials need list/read/write/delete access to the CNPG prefix as well
as the existing Restic repositories. No Restic password is used by Barman.

Archives are stored under
`${SECRET_CNPG_BACKUP_PATH}/${CNPG_NAMESPACE}/${CNPG_SERVER_NAME}/`; Barman adds the
server-name directory, which defaults to the cluster name. Each cluster has its
own `ObjectStore` and retention.

The Barman plugin is installed centrally in `cnpg-system`. Its Flux Kustomization
waits for CNPG and cert-manager; applications wait for Barman and Ceph before
reconciling their database resources.

## Layout

| Path | Contents |
| --- | --- |
| `base/` | The `Cluster` with `initdb` bootstrap |
| `backup/` | `ObjectStore`, credentials, `ScheduledBackup`, and the Barman plugin on the Cluster |
| `.` (this directory) | `base` + `backup`; what apps normally include |
| `without-backup/` | `base` only |
| `recovery/` | `base` + `backup`, bootstrapped from an existing archive |
| `recovery-target/` | Add-on for `recovery/` that stops at a point in time |

## Explicit opt-out

For disposable databases, include `../../../../components/cnpg/without-backup`
instead. This creates the same database without the plugin configuration,
credentials, object store, or schedule. Only `APP`, `CNPG_DATABASE`, and
`CNPG_OWNER` are required for this variant. Depend on `cloudnative-pg` and
`rook-ceph-cluster` rather than `barman-cloud`.

Switching an existing app to this variant removes its managed backup resources
and stops WAL archiving. It does not delete existing S3 objects. Backups are
automatic for databases created through the main component; independently
declared CNPG clusters are outside its scope.

## Migrating existing apps

Keep the same app name, namespace, database, owner, PostgreSQL version, and storage
settings. Remove `postgres.yaml` and its entry from the app's `kustomization.yaml`
in the same change that adds the component. The rendered Cluster retains the
same Kubernetes identity and Flux owner, so this updates it in place. Enabling
the Barman sidecar can roll the PostgreSQL pods.

After reconciliation, check that the schedule's first backup completes and that
WAL archiving succeeds:

```sh
kubectl -n default get clusters.postgresql.cnpg.io
kubectl -n default get objectstores.barmancloud.cnpg.io
kubectl -n default get scheduledbackups.postgresql.cnpg.io
kubectl -n default get backups.postgresql.cnpg.io
```

## Recovery

The main component bootstraps with `initdb`: if the Cluster and its volumes are
lost, Flux recreates an **empty** database. Bootstrap settings only apply when a
Cluster is created, so restoring means switching to the `recovery` variant and
letting Flux create the Cluster again.

1. Find the archive to restore from: the app's current `CNPG_SERVER_NAME`
   (`${APP}-postgres` unless it was changed by an earlier recovery). Confirm it
   has at least one completed base backup; WAL alone cannot be restored.
2. Edit the app's `ks.yaml`:

   ```yaml
   components:
     - ../../../../components/cnpg/recovery   # was ../../../../components/cnpg
   postBuild:
     substitute:
       # ...existing APP / CNPG_* values unchanged...
       CNPG_RECOVERY_SERVER_NAME: example-postgres   # archive to restore from
       CNPG_SERVER_NAME: example-postgres-r2         # NEW name for future backups
   ```

   `CNPG_SERVER_NAME` **must differ** from `CNPG_RECOVERY_SERVER_NAME`, otherwise
   the restored cluster writes into the archive it was restored from. Suffix
   `-r2`, `-r3`, ... on each recovery.
3. Suspend the Flux Kustomization and remove the broken Cluster so it is
   recreated from the new bootstrap (CNPG deletes its PVCs with it). The app
   cannot connect meanwhile: `${APP}-postgres-rw` has no endpoints until the
   restore finishes.

   ```sh
   flux suspend ks example -n <namespace>
   kubectl -n <namespace> delete cluster example-postgres
   ```

4. Push the change, then `flux resume ks example -n <namespace>`. CNPG restores
   the latest base backup and replays WAL to the end of the archive. Watch with
   `kubectl -n <namespace> get cluster example-postgres -w`.
5. Check the app's data. The `${APP}-postgres-app` secret is regenerated, so
   apps reading it pick up the new password automatically.

Afterwards, switch back to the main component and drop
`CNPG_RECOVERY_SERVER_NAME` (the bootstrap change is accepted on a running
Cluster and ignored). Leaving the recovery component in place would make the
next rebuild restore from the old, stale archive. **Keep `CNPG_SERVER_NAME`** at
the new value: it is where backups now live and what the next recovery reads. The old archive is no longer pruned by retention; delete it from S3 once
the new archive has a completed base backup and you no longer need it.

For a point-in-time restore (e.g. undoing a bad migration), also list
`../../../../components/cnpg/recovery-target` **after** the recovery component
and set `CNPG_RECOVERY_TARGET_TIME` (RFC 3339, e.g. `"2026-11-25T12:00:00Z"`).
WAL replay stops there instead of at the end of the archive. Remove it along
with the recovery component once the cluster is up. Patches in the app's `kustomization.yaml` or the Flux
Kustomization's `spec.patches` do not reach the Cluster, because the component
is added after them.

See the [CNPG recovery guide](https://cloudnative-pg.io/docs/1.30/recovery/) and
[Barman plugin usage](https://cloudnative-pg.io/plugin-barman-cloud/docs/usage/).
