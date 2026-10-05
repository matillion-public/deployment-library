"""Unit tests for install-library.py.

Loaded by file path (see conftest.py) since its filename is hyphenated.
resolve_and_confirm_snow_connection and every `snow`/`schemachange`
subprocess call are mocked out - these never touch a real Snowflake
account.
"""

import os
import subprocess
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from conftest import load_module_from_path
from snowflake_connection import SnowConnection

MODULE_PATH = Path(__file__).resolve().parent.parent / "install-library.py"
install_library = load_module_from_path("install_library", MODULE_PATH)


def _fake_connection(**parameters):
    return SnowConnection(
        connection_name="ci", account="ORG-ACC", parameters=parameters
    )


def _run(argv, connection, mock_run, env=None):
    # SNOWFLAKE_PASSWORD by default: several cases below use a password-auth
    # shaped connection (no authenticator, no private_key_file), which main()
    # refuses outright without it. Pass env={} to exercise that refusal.
    environ = {"SNOWFLAKE_PASSWORD": "hunter2"} if env is None else env
    with patch("install_library.resolve_and_confirm_snow_connection", return_value=connection), \
         patch("install_library.subprocess.run", mock_run), \
         patch("install_library.shutil.which", return_value="/usr/bin/fake"), \
         patch.dict(os.environ, environ, clear=True), \
         patch("sys.argv", ["install-library.py", *argv]):
        install_library.main()


def test_full_parameter_set_forwarded_to_schemachange():
    mock_run = Mock()
    connection = _fake_connection(
        user="svc_user",
        role="SVC_ROLE",
        warehouse="wh",
        authenticator="SNOWFLAKE_JWT",
        private_key_file="/tmp/key.p8",
    )

    _run(["--connection", "ci", "--yes"], connection, mock_run)

    deploy_call = mock_run.call_args_list[-1]
    args = deploy_call.args[0]
    assert args[0] == "schemachange"

    def value_of(flag):
        return args[args.index(flag) + 1]

    assert value_of("--snowflake-account") == "ORG-ACC"
    assert value_of("--snowflake-user") == "svc_user"
    assert value_of("--snowflake-role") == "SVC_ROLE"
    assert value_of("--snowflake-warehouse") == "wh"
    assert value_of("--snowflake-authenticator") == "SNOWFLAKE_JWT"
    assert value_of("--snowflake-private-key-file") == "/tmp/key.p8"


def test_password_auth_without_env_password_exits_before_deploying():
    # A connection with no authenticator and no private_key_file is password
    # auth. schemachange only takes a password from SNOWFLAKE_PASSWORD, and
    # this script never puts one in argv - so with neither, it must refuse
    # rather than hand schemachange an account and user with no credential.
    mock_run = Mock()
    connection = _fake_connection(user="jsmith")

    with pytest.raises(SystemExit) as exc:
        _run(["--connection", "ci", "--yes"], connection, mock_run, env={})

    assert exc.value.code == 1
    mock_run.assert_not_called()


def test_password_auth_with_env_password_proceeds():
    mock_run = Mock()
    connection = _fake_connection(user="jsmith")

    _run(["--connection", "ci", "--yes"], connection, mock_run,
         env={"SNOWFLAKE_PASSWORD": "hunter2"})

    assert mock_run.call_args_list[-1].args[0][0] == "schemachange"


def test_key_pair_auth_does_not_require_env_password():
    # The guard keys on "no private_key_file", so a JWT connection must pass
    # with an empty environment.
    mock_run = Mock()
    connection = _fake_connection(
        user="svc_user", authenticator="SNOWFLAKE_JWT", private_key_file="/tmp/key.p8"
    )

    _run(["--connection", "ci", "--yes"], connection, mock_run, env={})

    assert mock_run.call_args_list[-1].args[0][0] == "schemachange"


def test_missing_optional_parameters_are_omitted():
    # Password-auth-shaped connection: no role/warehouse/private_key_file.
    mock_run = Mock()
    connection = _fake_connection(user="jsmith")

    _run(["--connection", "ci", "--yes"], connection, mock_run)

    args = mock_run.call_args_list[-1].args[0]
    assert "--snowflake-role" not in args
    assert "--snowflake-warehouse" not in args
    assert "--snowflake-private-key-file" not in args
    # authenticator falls back to "snowflake" when the connection doesn't
    # set one (password auth).
    idx = args.index("--snowflake-authenticator")
    assert args[idx + 1] == "snowflake"


def test_database_is_created_before_schemachange_runs():
    mock_run = Mock()
    connection = _fake_connection(user="svc_user")

    _run(["--connection", "ci", "--yes"], connection, mock_run)

    first_call_args = mock_run.call_args_list[0].args[0]
    assert first_call_args[0] == "snow"
    assert "CREATE DATABASE IF NOT EXISTS matillion_runners;" in first_call_args


def test_config_file_forwarded_as_snow_global_arg():
    mock_run = Mock()
    connection = _fake_connection(user="svc_user")

    _run(
        ["--connection", "ci", "--config-file", "/tmp/config.toml", "--yes"],
        connection,
        mock_run,
    )

    snow_call_args = mock_run.call_args_list[0].args[0]
    assert snow_call_args[:3] == ["snow", "--config-file", "/tmp/config.toml"]


def test_custom_sql_root_forwarded_to_schemachange():
    mock_run = Mock()
    connection = _fake_connection(user="svc_user")

    _run(
        ["--connection", "ci", "--sql-root", "/tmp/sql-modified", "--yes"],
        connection,
        mock_run,
    )

    deploy_args = mock_run.call_args_list[-1].args[0]
    idx = deploy_args.index("--schemachange-root-folder")
    assert deploy_args[idx + 1] == "/tmp/sql-modified"


def test_default_sql_root_points_at_sibling_sql_dir():
    with patch("sys.argv", ["install-library.py"]):
        parsed = install_library.parse_args()
    assert Path(parsed.sql_root) == (MODULE_PATH.parent / "..").resolve() / "sql"


def test_missing_required_command_exits_before_any_snow_call():
    mock_run = Mock()

    def which(name):
        return None if name == "schemachange" else "/usr/bin/snow"

    with patch("install_library.shutil.which", side_effect=which), \
         patch("install_library.subprocess.run", mock_run), \
         patch("sys.argv", ["install-library.py", "--yes"]), \
         pytest.raises(SystemExit) as exc:
        install_library.main()

    assert exc.value.code == 1
    mock_run.assert_not_called()


@pytest.mark.parametrize(
    "failing_call, expected",
    [(0, "Creating the matillion_runners database failed (exit 3)"),
     (1, "schemachange deploy failed (exit 3)")],
)
def test_failed_subprocess_exits_with_message_not_traceback(failing_call, expected, capsys):
    calls = []

    def run(args, **kwargs):
        calls.append(args)
        if len(calls) - 1 == failing_call:
            raise subprocess.CalledProcessError(3, args)

    connection = _fake_connection(user="svc_user")

    with pytest.raises(SystemExit) as exc:
        _run(["--connection", "ci", "--yes"], connection, Mock(side_effect=run))

    assert exc.value.code == 1
    assert expected in capsys.readouterr().err
    assert len(calls) == failing_call + 1
