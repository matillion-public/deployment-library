# Matillion Runner on Snowpark Container Services — deployment library

**Status: Preview.**

An alternative to installing the Runner via the Snowflake Native App. Instead of
a Marketplace app install, this installs a small schema of stored procedures
into your own Snowflake account, which you then `CALL` to deploy, update and
remove one or more Runner instances directly on Snowpark Container Services
(SPCS).

## Layout

| Path | What it is |
| --- | --- |
| `sql/V1.0.0__install_library.sql` | Versioned script — schemas, `admin.runners` registry, image repository, network rule, EAI, `runner_operator` role. Runs once per account, ever. |
| `sql/V1.0.1__certificate_and_driver_stages.sql` | Versioned script — the stages for custom certificates and external drivers. Runs once per account, ever. |
| `sql/R__stored_procedures.sql` | Repeatable script — helper functions and the deploy/remove/list/logs procedures. Reapplied whenever its content changes. |
| `sql/R__stored_procedures_lifecycle.sql` | Repeatable script — `scale_runner`, `stop_runner`, `start_runner`, `restart_runner`. |
| `sql/R__stored_procedures_rollback.sql` | Repeatable script — `update_runner_image`, `rollback_runner_image`. |
| `scripts/install-library.py` | Deploys `sql/` via [schemachange](https://github.com/Snowflake-Labs/schemachange). The entry point for everything below. |
| `CHANGELOG.md` | What each release changed, and what to do when upgrading to it. |
| `requirements.txt` | Pinned versions of schemachange and the Snowflake CLI. The single place to bump them. |
| `schemachange-config.yml` | schemachange config. Change-history table lives at `MATILLION_RUNNERS.PUBLIC.CHANGE_HISTORY`. |

## Prerequisites

Python 3.10+, [schemachange](https://github.com/Snowflake-Labs/schemachange),
and the [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)
(`snow`), at the versions pinned in `requirements.txt`. Install them with
[pipx](https://pipx.pypa.io/), from this directory:

```bash
pipx install schemachange --pip-args="-c $PWD/requirements.txt"
pipx install snowflake-cli --pip-args="-c $PWD/requirements.txt"
```

`-c` reads `requirements.txt` as a constraints file, so pipx installs exactly
the pinned versions. A bare `pip install` fails on current
Homebrew Python (`error: externally-managed-environment`). If you already have
`snow` from Homebrew or elsewhere, check `snow --version` against the pin.

### A dedicated installer role

Create a role that exists only for this library, rather than using
`ACCOUNTADMIN` or another broad role: every runner role is granted to it (see
[Roles](#roles)), so it can act as the owner of every runner. Run this once, as
`SECURITYADMIN` or `ACCOUNTADMIN`:

```sql
CREATE ROLE <INSTALLER_ROLE>;
GRANT ROLE <INSTALLER_ROLE> TO USER <installing_user>;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE <INSTALLER_ROLE>;
GRANT CREATE COMPUTE POOL ON ACCOUNT TO ROLE <INSTALLER_ROLE>;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE <INSTALLER_ROLE>;
GRANT CREATE ROLE ON ACCOUNT TO ROLE <INSTALLER_ROLE>; -- runner_operator, and a role per runner
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE <INSTALLER_ROLE>; -- if not reusing one
GRANT USAGE ON WAREHOUSE <warehouse> TO ROLE <INSTALLER_ROLE> WITH GRANT OPTION; -- for the install session, and each runner's warehouse_name
```

Each runner's `warehouse_name` must be owned by `<INSTALLER_ROLE>`, or granted
to it `WITH GRANT OPTION` as above, because `deploy_runner` grants it on to the
runner's own role.

Don't grant `<INSTALLER_ROLE>` to other roles for convenience: every role
above it in the hierarchy can act as the owner of every runner.

### A Snowflake CLI connection for that role

Add a connection that uses `<INSTALLER_ROLE>` to the Snowflake CLI's
[`config.toml`](https://docs.snowflake.com/en/developer-guide/snowflake-cli/connecting/configure-cli).
Its default location depends on the operating system; `snow --info` prints it
as `default_config_file_path`.

Key-pair (`SNOWFLAKE_JWT`) and `externalbrowser` connections work as-is. A
password-auth connection also needs `SNOWFLAKE_PASSWORD` exported — see
[Limitations](#limitations).

### Roles

| Role | Created by | Used for |
| --- | --- | --- |
| `<INSTALLER_ROLE>` | You, once | Installing the library. It owns the database, compute pools, EAI and procedures, and every procedure runs as it. |
| `runner_operator` | Step 1 | Day-to-day operation: creating credentials and pipeline secrets, uploading certificates and drivers, and calling the procedures. |
| `<RUNNER_NAME>_RUNNER_ROLE` | `deploy_runner`, one per runner | Owning that runner's service. |

A service runs with its owner role's privileges
([Snowflake docs](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-services#label-spcs-manage-service-related-privileges)),
and its ownership can't be transferred. So `deploy_runner` creates each service
as that runner's own role, which holds only what the container needs: `USAGE`
on the database, its schemas, its compute pool, the EAI and its warehouse,
`READ` on the image repository and the certificate and driver stages, and
`READ` and `USAGE` on its own secrets.
It can also create functions in `runners`, which it uses to read pipeline
secrets, and create secrets in `secrets` (see [Pipeline secrets](#pipeline-secrets)).
It can't create anything else, can't replace objects it doesn't own, and one
runner can't read another's secrets.

To give a runner access to data, grant a role to its runner role, for
example one role per environment:

```sql
GRANT ROLE <prod_data_role> TO ROLE PROD_RUNNER_RUNNER_ROLE;
```

Each runner role is granted to `<INSTALLER_ROLE>`, which is how the other
procedures manage the service.

## 1. Install the library

Clone [matillion-public/deployment-library](https://github.com/matillion-public/deployment-library)
and run everything below from its `runner/snowflake` directory:

```bash
./scripts/install-library.py --connection installer_account
```

Add `--config-file PATH` if that connection lives somewhere other than the
Snowflake CLI's default `config.toml`.

It resolves the named connection, prints which account it is about to act
against, and asks for confirmation before running any DDL — pass `--yes` to skip
the prompt in automation. Rerunning it is safe: schemachange reapplies `R__`
scripts whose content has changed and skips everything else.

To see exactly what has been applied to an account, and when:

```sql
SELECT * FROM matillion_runners.public.change_history ORDER BY installed_on;
```

## 2. Push the Runner image to the account

Copy the Runner image from Matillion's public ECR repository into the image
repository step 1 created, `matillion_runners.admin.runner_images`. Tag it with
something unique to that image (below, the first 12 characters of its image ID)
and never reuse a tag (see [Why every image needs its own tag](#why-every-image-needs-its-own-tag)).

```bash
CONN=installer_account                            # your Snowflake CLI connection
SOURCE=public.ecr.aws/matillion/etl-agent:current

REPO_URL=$(snow spcs image-repository url runner_images \
  --database matillion_runners --schema admin --connection "$CONN")
snow spcs image-registry login --connection "$CONN"

docker pull --platform linux/amd64 "$SOURCE"
TAG=$(docker inspect --format '{{.Id}}' "$SOURCE" | cut -d: -f2 | cut -c1-12)
docker tag "$SOURCE" "$REPO_URL/agent:$TAG"
docker push "$REPO_URL/agent:$TAG"
```

`REPO_URL` has the form
`<org>-<account>.registry.snowflakecomputing.com/matillion_runners/admin/runner_images`,
lowercased and with underscores turned into hyphens. You can also read it from
the `repository_url` column of:

```sql
SHOW IMAGE REPOSITORIES IN SCHEMA matillion_runners.admin;
```

The last line of the `docker push` output has the digest:
`<tag>: digest: sha256:<digest> size: <n>`. To look it up later, run:

```sql
SHOW IMAGES IN IMAGE REPOSITORY matillion_runners.admin.runner_images;
```

Step 4 takes `$REPO_URL/agent@sha256:<digest>` as the image path.

### Why every image needs its own tag

`ALTER SERVICE ... FROM SPECIFICATION` restarts the container only when the
spec text changes, `image:` string included. Pushing new content under an
existing tag leaves the spec unchanged, so the running runner never picks it up.
Tagging by image ID guarantees a new tag for every new image.

## 3. Grant day-to-day access

`V1.0.0__install_library.sql` creates the `runner_operator` role but does not
grant it to anyone. Grant it to each operator, along with a warehouse to run
their sessions in:

```sql
GRANT ROLE runner_operator TO USER <operator>;
GRANT USAGE ON WAREHOUSE <warehouse> TO ROLE runner_operator;
```

The remaining steps run as `runner_operator`.

## 4. Set credentials, then deploy

```sql
USE ROLE runner_operator;

CREATE OR REPLACE SECRET matillion_runners.secrets.prod_runner_credentials
    TYPE = PASSWORD USERNAME = '<client_id>' PASSWORD = '<client_secret>';

CALL matillion_runners.admin.deploy_runner(
    runner_name => 'prod_runner',
    image_path => '<REPO_URL>/agent@sha256:<digest>',     -- from step 2
    warehouse_name => 'RUNNER_WH',                        -- must already exist; see "Prerequisites"
    account_id => '<matillion_account_id>',
    agent_id => '<matillion_agent_id>',
    matillion_region => 'eu1',
    -- Optional, shown with their defaults:
    instances => 1,
    instance_family => 'CPU_X64_XS',
    matillion_env => '',
    export_logs => TRUE,
    default_keyvault => NULL                              -- see "Pipeline secrets"
);
```

Leave out any optional argument you don't need to change. Arguments are
passed by name, so they can go in any order.

The secret must be named `<runner_name>_credentials`. `deploy_runner` refuses
to run if it is missing or is not `TYPE = PASSWORD`, rather than creating a
service that will crash-loop. To rotate the credentials, run the
`CREATE OR REPLACE SECRET` again; the runner picks up the new value the next
time its container starts, which `restart_runner` forces.

### Why credentials are a plain CREATE SECRET

A `CALL` statement's argument text is kept verbatim in `QUERY_HISTORY` for the
account's retention window (~1 year), readable by anyone with sufficient
monitoring grants. A `CREATE SECRET` has its secret value redacted there (the
`USERNAME`, the client ID, stays visible). So the client secret is never
passed to a procedure.

## 5. Check it is running

`deploy_runner` returns as soon as the service has been created, before the
runner is up.

```sql
CALL matillion_runners.admin.list_runners();
SHOW SERVICE CONTAINERS IN SERVICE matillion_runners.runners.prod_runner;
```

The container reports `READY` once the runner has registered with Matillion,
usually a couple of minutes after the compute pool has started, and the agent
then shows as connected in Matillion. If it does not get there, read the logs:

```sql
CALL matillion_runners.admin.get_runner_logs('prod_runner', 500);
```

## Pipeline secrets

The runner looks up the secrets your pipelines use in its keyvault,
`matillion_runners.secrets` unless told otherwise. Create them there as
`runner_operator`, with
[`CREATE SECRET`](https://docs.snowflake.com/en/sql-reference/sql/create-secret),
then grant each one to the runners that should see it:

```sql
GRANT READ, USAGE ON SECRET matillion_runners.secrets.<secret_name> TO ROLE PROD_RUNNER_RUNNER_ROLE;
```

Secrets created for the agent from Matillion are written by the runner itself,
as its runner role, so they need no grant: `deploy_runner` gives each runner
`CREATE SECRET` on `matillion_runners.secrets`.

To use a different schema, set `default_keyvault => '<database>.<schema>'` in
the `deploy_runner` call from step 4, then grant it to the runner role that
call created:

```sql
GRANT USAGE ON DATABASE <database> TO ROLE PROD_RUNNER_RUNNER_ROLE;
GRANT USAGE ON SCHEMA <database>.<schema> TO ROLE PROD_RUNNER_RUNNER_ROLE;
GRANT READ, USAGE ON SECRET <database>.<schema>.<secret_name> TO ROLE PROD_RUNNER_RUNNER_ROLE; -- each secret
GRANT CREATE SECRET ON SCHEMA <database>.<schema> TO ROLE PROD_RUNNER_RUNNER_ROLE; -- to create secrets from Matillion
```

`deploy_runner` only checks that `default_keyvault` has the form
`<database>.<schema>`, not that the runner can read it.

## Custom certificates and external drivers

Each runner mounts its own folder of two stages, which `runner_operator` can
upload to. The folder is the runner's name in lowercase, whatever case it was
deployed with: `prod_runner/` for `prod_runner` or `PROD_RUNNER`.

| Stage | Mounted at | Files the runner reads |
| --- | --- | --- |
| `matillion_runners.admin.custom_certificates_stage/<runner_name>/` | `/mnt/certificates` | `.cer`, `.pem`, `.crt` |
| `matillion_runners.admin.external_drivers_stage/<runner_name>/` | `/mnt/drivers` | `.jar`, `.so`, `.json`, `.lic`, `.sso` |

`deploy_runner` creates both folders, each with a `README.txt` that the
runner ignores: the service mounts the folders, so they have to exist before
anything is uploaded. The runner reads only files directly in its folder, not
in subfolders, and only when its container starts. To give several runners
the same file, upload it to each runner's folder.

1. Upload the files, either in Snowsight (**Catalog** → **Database Explorer** →
   `MATILLION_RUNNERS` → `ADMIN` → **Stages** → the stage → **+ Files**, with
   the runner's folder as the path) or with the Snowflake CLI:

   ```bash
   snow stage copy ./my-ca.pem @matillion_runners.admin.custom_certificates_stage/prod_runner/ \
     --overwrite --connection <operator_connection> --role runner_operator
   snow stage copy ./my-driver.jar @matillion_runners.admin.external_drivers_stage/prod_runner/ \
     --overwrite --connection <operator_connection> --role runner_operator
   ```

   With `PUT` from SnowSQL or another client, add `AUTO_COMPRESS = FALSE`.
   `PUT` compresses by default, and the runner ignores a `.jar.gz`.

2. Check what is there:

   ```sql
   USE ROLE runner_operator;
   LIST @matillion_runners.admin.external_drivers_stage/prod_runner/;
   ```

3. Restart each runner that should use them, after
   [pausing it](https://docs.maia.ai/docs/guides/pause-runner#pausing-a-maia-runner)
   in Matillion:

   ```sql
   CALL matillion_runners.admin.restart_runner('prod_runner');
   ```

   Then check that it is running, as in [step 5](#5-check-it-is-running).
   Its logs list each certificate imported and each driver added to the
   classpath.

To remove a file, `REMOVE @matillion_runners.admin.external_drivers_stage/prod_runner/my-driver.jar;`,
then restart the runner again.

`remove_runner` leaves the runner's folders in place, since a procedure
can't remove stage files. A runner deployed again under the same name picks
them up. To remove them, as `runner_operator`:

```sql
REMOVE @matillion_runners.admin.custom_certificates_stage/prod_runner/;
REMOVE @matillion_runners.admin.external_drivers_stage/prod_runner/;
```

Keep the trailing `/`: `REMOVE` matches by prefix, so without it
`.../prod_runner` would also remove `prod_runner_2/`.

The folders keep runners' files apart, but they aren't access control: a
runner's role can read the whole of both stages. Don't upload anything a
runner shouldn't be able to read, such as an Oracle auto-login wallet
(`.sso`) meant for another runner.

A driver usually also needs:

- **A secret** for the database's password. Create it as a pipeline secret
  (see [Pipeline secrets](#pipeline-secrets)). The public docs describe
  [secrets for a Snowflake-hosted runner](https://docs.matillion.com/data-productivity-cloud/agent/docs/snowflake-agent-secrets/).
- **The database's port.** The network rule allows every host, but only on
  ports 443 and 80. For a database on another port, add it as
  `<INSTALLER_ROLE>`, which owns the rule, keeping the existing entries:

  ```sql
  USE ROLE <INSTALLER_ROLE>;
  ALTER NETWORK RULE matillion_runners.admin.all_access_rule
      SET VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80', '<host>:<port>');
  ```

Runners deployed before the library had these stages don't mount them until
their service is next updated. See [The library](#the-library) under Updating.

## Updating

### The library

Pull the latest version of this repository, then rerun step 1:

```bash
git pull
./scripts/install-library.py --connection installer_account
```

Then check what was applied with the `change_history` query from step 1. A
release that changes nothing in `sql/` applies nothing.

Then follow the **Upgrading** steps in [CHANGELOG.md](CHANGELOG.md) for each
release since the one you had.

A release that changes the service spec reaches a runner only when its
service is next updated: by `update_runner_image`, `rollback_runner_image` or
a `deploy_runner` rerun. `restart_runner` doesn't apply it. To apply it
without changing the image, pass the image the runner is already running,
shown by `list_runners`:

```sql
CALL matillion_runners.admin.update_runner_image('prod_runner', '<current image>');
```

This restarts the runner, so pause it in Matillion first. The certificate and
driver stages are such a change.

### The Runner image

Matillion publishes new Runner images to `public.ecr.aws/matillion/etl-agent`.
Watch it for new releases, and for each one you want to run:

1. [Pause the runner](https://docs.maia.ai/docs/guides/pause-runner#pausing-a-maia-runner)
   in Matillion. The update restarts the container, which interrupts any work
   in flight on it.
2. Push the new image into the account under a new tag, as in step 2.
3. Roll it out, with the image path from that push:

   ```sql
   USE ROLE runner_operator;
   CALL matillion_runners.admin.update_runner_image(
       'prod_runner', '<REPO_URL>/agent@sha256:<digest>');
   ```

4. Check the returned message. The procedures don't raise, so a `CALL` that
   completes can still have failed.
5. Check it is running, as after a deploy ([step 5](#5-check-it-is-running)),
   then resume it in Matillion.

If the new image doesn't work, roll back to the one it replaced:

```sql
CALL matillion_runners.admin.rollback_runner_image('prod_runner');
```

Rollback is one level deep: calling it a second time moves forward to the
newer image again. To go further back, pass the older image path to
`update_runner_image`.

`update_runner_image` changes only the image. To change other settings at the
same time, rerun your step 4 `deploy_runner` call with the new `image_path`
instead.

## Uninstalling

Run this as `<INSTALLER_ROLE>`. `list_runners` shows which runners to remove:

```sql
USE ROLE <INSTALLER_ROLE>;
CALL matillion_runners.admin.list_runners();
CALL matillion_runners.admin.remove_runner('<runner_name>'); -- each runner

DROP DATABASE matillion_runners;
DROP INTEGRATION matillion_runner_eai;
DROP ROLE runner_operator;
```

`remove_runner` drops each runner's service, compute pool, role and secrets.
`DROP DATABASE` removes everything else the library created inside
`matillion_runners`: the procedures, the image repository and its images,
the certificate and driver stages and their files, the network rule, the
change history, and any pipeline secrets in `matillion_runners.secrets`.
Pipeline secrets in another keyvault, and your warehouses, are left alone.

The integration is an account-level object, so `DROP DATABASE` doesn't remove
it. Drop it before the installer role: when a role is dropped, what it owns
passes to the role that dropped it, and a later install would then reuse that
leftover integration (see [Troubleshooting](#troubleshooting)).

Finally, as `SECURITYADMIN` or `ACCOUNTADMIN`:

```sql
DROP ROLE <INSTALLER_ROLE>;
```

## Procedure reference

All procedures live in `matillion_runners.admin` and run `EXECUTE AS OWNER`, so
the day-to-day `runner_operator` role never needs the underlying
`CREATE COMPUTE POOL` / `CREATE INTEGRATION` privileges — only `USAGE` on the
schemas, `EXECUTE` on the procedures, `CREATE SECRET` in `secrets` for
credentials and pipeline secrets, and `READ` and `WRITE` on the certificate
and driver stages.

| Procedure | Purpose |
| --- | --- |
| `deploy_runner(runner_name, image_path, warehouse_name, account_id, agent_id, matillion_region, [instances], [instance_family], [matillion_env], [export_logs], [default_keyvault])` | Create a runner, or re-apply desired state to an existing one. |
| `remove_runner(runner_name)` | Drop the service, its runner role, compute pool, the runner's own secrets (credentials included), and the registry row. Pipeline secrets and its certificate and driver folders are left alone. |
| `list_runners()` | Every registered runner, with its service's live status: `MISSING` if the service has been dropped outside the library. |
| `get_runner_logs(runner_name, [num_lines])` | Container logs for a runner. |
| `scale_runner(runner_name, instances)` | Set the runner's instance count, resizing the service **and** its compute pool together. Runners don't autoscale. |
| `stop_runner(runner_name)` / `start_runner(runner_name)` | Suspend / resume the service. |
| `restart_runner(runner_name)` | Suspend, wait for `SUSPENDED`, resume. Ungraceful — see below. |
| `update_runner_image(runner_name, new_image_path)` | Roll a new image out to a running runner. |
| `rollback_runner_image(runner_name)` | Roll back to the previously-running image. One level deep — see below. |

`runner_name` is case-insensitive to the caller and stored uppercase. Object
names are derived from it (`<RUNNER_NAME>_RUNNER_POOL` for the compute pool,
`RUNNERS.<RUNNER_NAME>` for the service, `<RUNNER_NAME>_RUNNER_ROLE` for its
role), so one installed library can manage
several independent runners in the same account — one per environment, say.

These procedures validate and return a message string; they do not raise. Check
the returned value rather than assuming a completed `CALL` means success.

Re-applying `deploy_runner` with a different account ID, agent ID, region,
environment, `export_logs` or `default_keyvault` updates the runner's secrets.
The running container picks them up the next time it starts; `restart_runner`
forces that.

## Troubleshooting

**Service never reaches READY.** `CALL admin.get_runner_logs('<name>')`. A
crash-loop immediately after deploy is usually a missing or wrong secret;
`deploy_runner` guards a missing or wrong-type credentials secret specifically.

**`deploy_runner` fails with `Image ... not found`.** The image path doesn't
match an image in `matillion_runners.admin.runner_images`. Push the image
(step 2) first, and copy the path from its `docker push` output.

**`deploy_runner` fails with `Grant not executed: Insufficient privileges`.**
Usually a `matillion_runner_eai` integration left over from an earlier install:
step 1 keeps an existing integration rather than replacing it, so a leftover
one owned by another role is never handed to `<INSTALLER_ROLE>`. Check its owner
with `SHOW GRANTS ON INTEGRATION matillion_runner_eai`. If it isn't
`<INSTALLER_ROLE>`, drop it as its owner (or `ACCOUNTADMIN`), then recreate it
as `<INSTALLER_ROLE>`:

```sql
CREATE EXTERNAL ACCESS INTEGRATION matillion_runner_eai
    ALLOWED_NETWORK_RULES = (matillion_runners.admin.all_access_rule)
    ALLOWED_AUTHENTICATION_SECRETS = ALL
    ENABLED = true;
```

**A pipeline can't find a secret.** The runner reads secrets as its own role,
so each pipeline secret needs `READ` and `USAGE` granted to
`<RUNNER_NAME>_RUNNER_ROLE` — see [Pipeline secrets](#pipeline-secrets).

**A certificate or driver isn't picked up.** The runner logs each file it
imports when its container starts. If one is missing, check that the file is
directly in the runner's folder, named in lowercase, not in a subfolder; that
it wasn't compressed on upload (`LIST` shows a `.gz` name); and that the
runner was restarted after the upload. A runner deployed before the library had these stages
also needs its service updated once — see [The library](#the-library).

**A redeploy reported success but nothing changed.** Almost always an image tag
that was overwritten in place rather than a fresh immutable tag — see step 2.

## Limitations

- **Password auth needs `SNOWFLAKE_PASSWORD` in the environment.**
  `install-library.py` forwards account, user, role, warehouse, authenticator
  and private-key file to schemachange as explicit flags, but deliberately
  never puts a password in argv — schemachange reads it from that environment
  variable instead. The script checks for it up front and fails with that
  message rather than letting schemachange fail obscurely.
- **Egress is open to every host on ports 443 and 80.** The EAI is created
  with `VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80')` and
  `ALLOWED_AUTHENTICATION_SECRETS = ALL`, matching what the Native App grants
  today. Other ports have to be added, as for a driver's database (see
  [Custom certificates and external drivers](#custom-certificates-and-external-drivers)).
  Narrow the `VALUE_LIST` to known hosts if a tighter allow-list is wanted for
  a given account.
- **Rollback is one level deep.** Only the image before the current one is
  kept, so calling `rollback_runner_image` twice in a row moves forward again.
  Updating to the image already running doesn't lose it. To go further back,
  pass the image path to `update_runner_image`.
- **Restarting interrupts running pipelines.** `restart_runner`, and any
  change to the service such as a new image, interrupts work in flight on the
  container. [Pause the runner](https://docs.maia.ai/docs/guides/pause-runner#pausing-a-maia-runner)
  in Matillion first, and resume it once the restart has finished.
- **Instance families larger than `CPU_X64_XS` may over-provision the compute
  pool.**
- **Runners can read each other's certificates and drivers.** Each runner
  mounts only its own folder, but its role can read the whole stage with SQL.
- **`install-library.py` may open an SSO browser prompt for your default
  connection.** If the `default_connection_name` in `config.toml` uses
  `externalbrowser`, a browser window can open for it before the confirmation
  prompt, even when you pass a different `--connection`.
