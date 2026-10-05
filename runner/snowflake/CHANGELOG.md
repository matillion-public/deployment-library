# Changelog — Snowflake runner library

Each release that changes `sql/` has an entry here, with what to do when
upgrading to it. A release adds a versioned script only when it has one-off
changes, named after the release: `V1.0.1__...` is release 1.0.1. Releases
that only change the repeatable `R__` scripts have no versioned script of
their own.

To upgrade, rerun the installer (see [README](README.md#the-library)), then
follow the **Upgrading** steps of every release since the one you have. To see
which you have, check which versioned scripts have been applied:

```sql
SELECT script, installed_on FROM matillion_runners.public.change_history
WHERE script_type = 'V' ORDER BY installed_on;
```

## 1.0.1

Custom certificates and external drivers (DPC-58365).

Runners deployed with the library could use neither, because the service spec
had none of the Native App's volumes for them. Each runner now mounts its own
folder of two stages, `custom_certificates_stage/<runner_name>/` and
`external_drivers_stage/<runner_name>/`, and loads what it finds there when
its container starts. See [Custom certificates and external drivers](README.md#custom-certificates-and-external-drivers).

### Added

- `V1.0.1__certificate_and_driver_stages.sql`: the two stages in
  `matillion_runners.admin`, with `READ` and `WRITE` on both for
  `runner_operator`, which uploads the files.
- The service spec mounts the runner's folders at `/mnt/certificates` and
  `/mnt/drivers`, and sets `CUSTOM_CERT_LOCATION` and
  `EXTERNAL_DRIVER_LOCATION` to match.
- `deploy_runner` and `update_runner_image` grant the runner role `READ` on
  both stages, and write a `README.txt` into each of its folders so they exist
  before anything is uploaded.

### Changed

- `remove_runner` leaves the runner's folders in place: a procedure can't
  remove stage files. The README has the `REMOVE` statements to clear them.

### Upgrading

Existing runners don't mount the folders until their service is next updated.
For each runner, [pause it](https://docs.maia.ai/docs/guides/pause-runner#pausing-a-maia-runner)
in Matillion, then update it to the image it is already running, shown by
`list_runners`:

```sql
USE ROLE runner_operator;
CALL matillion_runners.admin.update_runner_image('<runner_name>', '<current image>');
```

This restarts the runner. Rerunning its `deploy_runner` call works too.

A database a driver connects to on a port other than 443 or 80 also needs
that port added to the network rule. See the README.

## 1.0.0

First release: install the library with schemachange, then deploy and manage
runners on Snowpark Container Services by calling its procedures.

### Added

- `V1.0.0__install_library.sql`: the `matillion_runners` database with its
  `admin`, `runners` and `secrets` schemas, the `admin.runners` registry, the
  `runner_images` image repository, the network rule and
  `matillion_runner_eai`, and the `runner_operator` role.
- `deploy_runner`, `remove_runner`, `list_runners` and `get_runner_logs`. Each
  runner's service is owned by its own `<RUNNER_NAME>_RUNNER_ROLE`, holding
  only what the container needs.
- `scale_runner`, `stop_runner`, `start_runner` and `restart_runner`.
- `update_runner_image` and `rollback_runner_image`, one level deep.
