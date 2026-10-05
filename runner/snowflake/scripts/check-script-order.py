#!/usr/bin/env python3
"""check-script-order.py

Fails if schemachange would not apply the repeatable (R__) scripts in an
order that satisfies their dependencies.

schemachange applies all versioned (V) scripts first, then all repeatable
(R), then all always (A), sorting each group by filename - see
schemachange/deploy.py. It offers no way to declare a dependency between two
repeatable scripts, so their relative order rests entirely on what the files
happen to be called.

That makes the ordering implicit and silent: renaming a script, or adding one
that sorts earlier, reorders the deploy with nothing in the diff to say so.
R__stored_procedures.sql currently sorts first only because "." (0x2E)
precedes "_" (0x5F), which is an accident of punctuation rather than a
decision anyone recorded. This check turns that accident into a stated rule.

Imports schemachange's own sort rather than reimplementing it, so there is
one source of truth. That requires the pinned version in
runner/snowflake/requirements.txt - schemachange.version does not exist in
4.0.1 - and an ImportError here means the pin moved and the module with it,
which is exactly when the ordering assumption is worth re-reading.

Whether the order is load-bearing today is a separate question: Snowflake
does not appear to resolve names inside a procedure body at CREATE time, so
defining a helper after its caller may well be harmless. This check is about
the ordering not changing by accident, not a claim that a wrong order breaks
the deploy.

Usage:
  ./check-script-order.py [SQL_DIR]     # defaults to ../sql
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from schemachange.version import sorted_alphanumeric
except ImportError as exc:
    print(
        "::error::Could not import schemachange.version.sorted_alphanumeric "
        f"({exc}). This is a private module of schemachange and has moved "
        "before (it does not exist in 4.0.1). If the pinned version in "
        "runner/snowflake/requirements.txt changed, re-check how that "
        "release orders repeatable scripts before updating this import.",
        file=sys.stderr,
    )
    sys.exit(1)

# Defines the helpers (is_valid_identifier, is_valid_image_ref,
# build_runner_spec, escape_sql_string, create_runner_folders) that every
# other repeatable script calls, so it has to be applied first.
HELPERS = "r__stored_procedures.sql"

DEFAULT_SQL_DIR = Path(__file__).resolve().parent.parent / "sql"


def main() -> int:
    sql_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SQL_DIR
    if not sql_dir.is_dir():
        print(f"::error::{sql_dir} is not a directory.", file=sys.stderr)
        return 1

    # Lowercased to match schemachange, which folds names before sorting and
    # decides a script's type from the first character of the folded name.
    repeatable = [
        p.name.lower() for p in sql_dir.glob("*.sql")
        if p.name.lower().startswith("r__")
    ]

    if HELPERS not in repeatable:
        print(
            f"::error::{HELPERS} is not in {sql_dir}. If it was renamed, update "
            "HELPERS in this check - after confirming the new name still sorts "
            "before every other R__ script.",
            file=sys.stderr,
        )
        return 1

    order = sorted_alphanumeric(repeatable)
    print("schemachange will apply the repeatable scripts in this order:")
    for i, name in enumerate(order, 1):
        print(f"  {i}. {name}")

    if order[0] != HELPERS:
        print(
            f"::error::{HELPERS} defines the helper functions every other "
            f"repeatable script calls, but schemachange would apply "
            f"'{order[0]}' first. Repeatable scripts are ordered by filename "
            "alone - renaming one, or adding one that sorts earlier, changes "
            "the deploy order with nothing in the diff to say so. Rename so "
            "the helpers sort first.",
            file=sys.stderr,
        )
        return 1

    print(f"OK: {HELPERS} sorts first of {len(repeatable)} repeatable script(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
