"""lib/snowflake_connection.py

Shared helper for resolving, displaying, and confirming which Snowflake CLI
connection - and which config file - a script is about to act against.
Meant to be imported, not run directly; it only defines
resolve_and_confirm_snow_connection(). The caller parses its own
--connection/--config-file/--yes flags (see install-library.py for the
parsing pattern) before calling it.

Why this exists: it's easy for a script like this to silently act against
whatever the Snowflake CLI's ambient default connection happens to be.
--connection/--config-file make the target explicit; this makes sure that
target - explicit or resolved - is always shown and confirmed before
anything happens, and that every `snow` call downstream is given the same
--config-file rather than only the first one.

NOTE: `snow connection list` is documented as reading local config.toml
only, with no authentication involved. In practice (observed on Snowflake
CLI 3.24.0), it triggered a real SSO browser prompt anyway - specifically
for whichever connection is that config's default_connection_name, if THAT
ONE happens to use `externalbrowser` auth, regardless of which --connection
was requested. A default connection on key-pair or password auth did not
trigger it. So: don't be surprised by a browser window for a connection you
didn't ask for, before you've even seen the confirmation prompt below.
"""

from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import dataclass


@dataclass
class SnowConnection:
    connection_name: str
    account: str
    parameters: dict[str, str]


def resolve_and_confirm_snow_connection(
    connection_name: str | None,
    config_file: str | None,
    assume_yes: bool,
    extra_lines: list[tuple[str, str]] | None = None,
) -> SnowConnection:
    """Resolves connection_name (if not given, to the config's default
    connection), looks up its account, prints a notice, and asks for
    confirmation - exiting rather than proceeding if it can't get an
    unambiguous yes. Returns the resolved connection name, account, and its
    full `parameters` dict (user, role, warehouse, authenticator, ...) in
    case the caller needs to pass those straight through elsewhere - e.g.
    install-library.py forwarding them to schemachange, which can't read the
    Snowflake CLI's own config.toml format itself.

    extra_lines are shown as additional "Label: value" lines in the notice,
    e.g. [("Destination repository", dest_repo)].
    """
    global_args = ["--config-file", config_file] if config_file else []
    suffix = f" --config-file {config_file}" if config_file else ""

    # Output is captured for the JSON, which would also swallow snow's own
    # error message on failure - print it rather than leaving the user a
    # CalledProcessError traceback that hides why (e.g. an unreadable or
    # malformed config file).
    try:
        result = subprocess.run(
            ["snow", *global_args, "connection", "list", "--format", "json"],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"`snow connection list{suffix}` failed (exit {e.returncode}):\n"
            f"{(e.stderr or e.stdout or '').strip()}",
            file=sys.stderr,
        )
        sys.exit(1)
    connections = json.loads(result.stdout)

    if not connection_name:
        defaults = [c for c in connections if c.get("is_default")]
        if not defaults:
            print(
                "Could not resolve a default Snowflake CLI connection - "
                "pass --connection NAME explicitly.",
                file=sys.stderr,
            )
            sys.exit(1)
        connection_name = defaults[0]["connection_name"]

    # These two failures are reported separately on purpose: "the connection
    # isn't there" and "the connection is there but has no account" send you
    # looking in completely different places, and collapsing them into one
    # "not found" message sends you to the wrong one half the time.
    matches = [c for c in connections if c.get("connection_name") == connection_name]
    if not matches:
        known = ", ".join(sorted(c.get("connection_name", "?") for c in connections))
        print(
            f"No connection named '{connection_name}' found via "
            f"`snow connection list{suffix}`.\n"
            f"Connections in that config: {known or '(none)'}",
            file=sys.stderr,
        )
        sys.exit(1)

    parameters = matches[0].get("parameters", {})
    account = parameters.get("account")
    if not account:
        print(
            f"Connection '{connection_name}' exists but defines no account - "
            f"add `account = ...` to it in the config "
            f"`snow connection list{suffix}` is reading.",
            file=sys.stderr,
        )
        sys.exit(1)

    lines = [("Snowflake CLI connection", connection_name), ("Account", account)]
    if config_file:
        lines.append(("Config file", config_file))
    lines.extend(extra_lines or [])

    print("+" + "-" * 67, file=sys.stderr)
    for label, value in lines:
        print(f"| {label:<25}: {value}", file=sys.stderr)
    print("+" + "-" * 67, file=sys.stderr)

    if not assume_yes:
        if sys.stdin.isatty():
            reply = input("Proceed with this connection? [y/N] ")
            if reply.strip().lower() not in ("y", "yes"):
                print("Aborted.", file=sys.stderr)
                sys.exit(1)
        else:
            print(
                "Not running in an interactive terminal - pass --yes to "
                "confirm non-interactively.",
                file=sys.stderr,
            )
            sys.exit(1)

    return SnowConnection(connection_name, account, parameters)
