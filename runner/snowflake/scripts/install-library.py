#!/usr/bin/env python3
"""install-library.py

Deploys ../sql/ (V1.0.0__install_library.sql, then R__stored_procedures.sql)
against a Snowflake account via schemachange
(https://github.com/Snowflake-Labs/schemachange), installing the Matillion
Runner deployment library: schemas, the admin.runners registry table, the
image repository, the network rule/external access integration, and the
admin.* stored procedures. This is step 1 of the runbook in ../README.md.

Why schemachange rather than plain `snow sql -f`: it tracks exactly what's
been applied and when (queryable directly - see ../README.md), and reruns
repeatable (R__) scripts automatically whenever their content changes,
without the customer needing to work out that anything changed at all. It
does not, on its own, make a procedure *signature* change safe - see the
note at the top of R__stored_procedures.sql for what a future edit that
changes a signature still needs to do by hand.

Requires: Python 3.10+, plus schemachange and the Snowflake CLI (`snow`) at
the versions in ../requirements.txt - see ../README.md, "Prerequisites".

Key-pair (SNOWFLAKE_JWT) and externalbrowser connections work as-is. A
password-auth connection additionally needs SNOWFLAKE_PASSWORD exported,
since schemachange only reads a password from the environment and this
script deliberately doesn't put one in argv - main() checks for it and
fails with that message rather than letting schemachange fail obscurely.

Usage:
  ./install-library.py [--connection NAME] [--config-file PATH] [--sql-root PATH] [--yes]

Example:
  ./install-library.py --connection installer_account

--config-file is only needed when the connection lives somewhere other than
the Snowflake CLI's default config.toml.

--sql-root defaults to ../sql (this library's own scripts) and should not
normally be overridden - it exists for CI to deploy a scratch
copy with a deliberately modified R__stored_procedures.sql, to verify a real
content change is picked up and reapplied without also rerunning
V1.0.0__install_library.sql.

Resolves and confirms its target connection via lib/snowflake_connection.py -
this NEVER runs DDL against whatever the Snowflake CLI's ambient default
connection happens to be without saying so first, and --config-file lets this
honour a repo-local config.toml instead of only the CLI's own global default.

schemachange's own connections.toml support does NOT understand the
Snowflake CLI's config.toml format - confirmed live, 20 Aug 2026: even
pointed at the right file, it looks for a bare top-level `[connection_name]`
table (the raw Snowflake connector's own older convention), not the CLI's
`[connections.connection_name]` nesting, so it reports the connection "not
found" and then fails with "User is empty". Rather than depend on
schemachange ever supporting that format, this extracts the resolved
connection's actual parameters via the same `snow connection list --format
json` resolve_and_confirm_snow_connection already ran, and passes them to
schemachange as explicit -a/-u/-r/-w/-d/-s/--snowflake-authenticator flags -
bypassing schemachange's file-based connection lookup entirely.

Shells out to the `snow` CLI and to `schemachange` rather than using the
Snowflake Python connector.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from snowflake_connection import resolve_and_confirm_snow_connection  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Install/update the Matillion Runner Snowflake deployment "
            "library via schemachange."
        )
    )
    parser.add_argument("--connection", help="Snowflake CLI connection name")
    parser.add_argument("--config-file", help="Snowflake CLI config.toml path")
    parser.add_argument(
        "--sql-root",
        default=str((SCRIPT_DIR / ".." / "sql").resolve()),
        help="schemachange root folder (defaults to ../sql - see module docstring)",
    )
    parser.add_argument("--yes", "-y", action="store_true", help="Skip the confirmation prompt")
    return parser.parse_args()


def require_commands(*names: str) -> None:
    missing = [n for n in names if shutil.which(n) is None]
    if missing:
        for name in missing:
            print(
                f"Required command not found: {name} - see README.md, "
                '"Prerequisites", for installing it at the pinned version',
                file=sys.stderr,
            )
        sys.exit(1)


def run_or_exit(args: list[str], what: str) -> None:
    """Runs a command whose output goes straight to the terminal, exiting
    with a one-line pointer to that output if it fails, rather than a
    CalledProcessError traceback burying it.
    """
    try:
        subprocess.run(args, check=True)
    except subprocess.CalledProcessError as e:
        print(f"{what} failed (exit {e.returncode}) - see its output above.", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    args = parse_args()
    require_commands("snow", "schemachange")

    # Resolve, display, and confirm which Snowflake connection is in play.
    # See lib/snowflake_connection.py for the SSO-prompt caveat around this
    # call.
    conn = resolve_and_confirm_snow_connection(
        connection_name=args.connection,
        config_file=args.config_file,
        assume_yes=args.yes,
        extra_lines=[
            (
                "Action",
                "Install schemas, registry table, image repository, "
                "network rule, EAI, and stored procedures (via schemachange)",
            )
        ],
    )

    # authenticator defaults to "snowflake" (the connector's own default)
    # when the connection doesn't set one, which is what a password-auth
    # config.toml looks like - it has no explicit authenticator key.
    user = conn.parameters.get("user") or ""
    role = conn.parameters.get("role") or ""
    warehouse = conn.parameters.get("warehouse") or ""
    authenticator = conn.parameters.get("authenticator") or "snowflake"
    # Only relevant for SNOWFLAKE_JWT auth, but harmless to resolve
    # unconditionally - empty for any connection that doesn't set it (e.g.
    # password auth).
    private_key_file = conn.parameters.get("private_key_file") or ""

    schemachange_conn_args = [
        "--snowflake-account", conn.account,
        "--snowflake-authenticator", authenticator,
    ]
    if user:
        schemachange_conn_args += ["--snowflake-user", user]
    if role:
        schemachange_conn_args += ["--snowflake-role", role]
    if warehouse:
        schemachange_conn_args += ["--snowflake-warehouse", warehouse]
    # Without this, SNOWFLAKE_JWT auth reaches schemachange with no key at
    # all ("Expected bytes, RSAPrivateKey, or EllipticCurvePrivateKey, got
    # NoneType") - confirmed live against a JWT-authenticated connection.
    if private_key_file:
        schemachange_conn_args += ["--snowflake-private-key-file", private_key_file]

    # Password auth has no equivalent flag to forward - schemachange takes the
    # password from SNOWFLAKE_PASSWORD in the environment, never from argv
    # (which would put it in the process table). Without it, schemachange gets
    # an account and a user and no credential, and fails somewhere further in
    # with nothing pointing at the real cause. Fail here instead, while there
    # is still something useful to say.
    #
    # NOT exercised by CI, which authenticates with a key pair -
    # the check below is the guard, not a claim that this path is tested.
    if authenticator.lower() == "snowflake" and not private_key_file:
        if not os.environ.get("SNOWFLAKE_PASSWORD"):
            print(
                f"Connection '{conn.connection_name}' looks like password auth "
                "(no authenticator and no private_key_file), but "
                "SNOWFLAKE_PASSWORD is not set.\n"
                "schemachange reads the password from that environment "
                "variable; this script cannot pass it on the command line.\n"
                "Either export SNOWFLAKE_PASSWORD, or use a key-pair "
                "(SNOWFLAKE_JWT) or externalbrowser connection.",
                file=sys.stderr,
            )
            sys.exit(1)

    global_args = ["--config-file", args.config_file] if args.config_file else []

    # schemachange's change-history-table setup (schemachange-config.yml)
    # only creates the SCHEMA and TABLE it needs, never the DATABASE -
    # confirmed live, 20 Aug 2026: on a fresh account it failed with
    # "Database 'METADATA' does not exist" before running a single script.
    # Pre-create just the bare database here (idempotent) so the change
    # history table has somewhere to live before V1.0.0__install_library.sql
    # itself gets a chance to run and build out the rest.
    print("Ensuring matillion_runners database exists...", file=sys.stderr)
    run_or_exit(
        [
            "snow", *global_args, "sql",
            "-q", "CREATE DATABASE IF NOT EXISTS matillion_runners;",
            "--connection", conn.connection_name,
        ],
        "Creating the matillion_runners database",
    )

    run_or_exit(
        [
            "schemachange", "deploy",
            "--schemachange-root-folder", args.sql_root,
            "--config-folder", str((SCRIPT_DIR / "..").resolve()),
            *schemachange_conn_args,
        ],
        "schemachange deploy",
    )

    print("Install complete.", file=sys.stderr)


if __name__ == "__main__":
    main()
