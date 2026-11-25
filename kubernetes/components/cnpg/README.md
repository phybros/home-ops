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

The first base backup is requested immediately when the schedule is created.
WAL archiving runs continuously because Barman's online backups require it, even
when only daily recovery points are needed.

The encrypted `cluster-secrets` supplies `SECRET_CNPG_BACKUP_PATH`, an S3 URL
separate from the Restic repositories. CNPG uses the existing
`SECRET_RESTIC_AWS_ACCESS_KEY_ID` and `SECRET_RESTIC_AWS_SECRET_ACCESS_KEY`.
Those credentials need list/read/write/delete access to the CNPG prefix as well
as the existing Restic repositories. No Restic password is used by Barman.

Archives are stored under
`${SECRET_CNPG_BACKUP_PATH}/${CNPG_NAMESPACE}/${APP}-postgres/`; Barman adds the
cluster-name directory. Each cluster has its own `ObjectStore` and retention.

The Barman plugin is installed centrally in `cnpg-system`. Its Flux Kustomization
waits for CNPG and cert-manager; applications wait for Barman and Ceph before
reconciling their database resources.

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

Backups do not change the default bootstrap behavior: the component creates an
empty database when no existing database volumes survive. For a disaster
recovery, restore a new cluster using `bootstrap.recovery` and an
`externalClusters` entry referencing the original `ObjectStore` and server name.
Replace `bootstrap.initdb`; do not leave both bootstrap methods configured.
Supply the original database and owner and restore or reset application
credentials. Use a separate archive location or server name for the recovered
cluster's future backups so it cannot overwrite the source archive.

See the [CNPG recovery guide](https://cloudnative-pg.io/docs/1.30/recovery/) and
[Barman plugin usage](https://cloudnative-pg.io/plugin-barman-cloud/docs/usage/).
