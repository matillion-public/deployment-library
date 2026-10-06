"""Unit tests for lib/snowflake_connection.py.

Every `snow` call is mocked out via subprocess.run - these never touch a
real Snowflake account (see ../../../.github/workflows/snowflake-test.yml
live-deploy job for that).
"""

import json
import subprocess
from unittest.mock import Mock, patch

import pytest

from snowflake_connection import resolve_and_confirm_snow_connection

CONNECTIONS = [
    {
        "connection_name": "ci",
        "is_default": True,
        "parameters": {
            "account": "ORG-ACC",
            "user": "svc_user",
            "role": "SVC_ROLE",
            "warehouse": "wh",
            "authenticator": "SNOWFLAKE_JWT",
            "private_key_file": "/tmp/key.p8",
        },
    },
    {
        "connection_name": "other",
        "is_default": False,
        "parameters": {"account": "OTHER-ACC"},
    },
]


def _mock_snow_result(payload):
    result = Mock()
    result.stdout = json.dumps(payload)
    return result


@patch("snowflake_connection.subprocess.run")
def test_resolves_default_connection_when_none_named(mock_run):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)

    conn = resolve_and_confirm_snow_connection(
        connection_name=None, config_file=None, assume_yes=True
    )

    assert conn.connection_name == "ci"
    assert conn.account == "ORG-ACC"
    assert conn.parameters["private_key_file"] == "/tmp/key.p8"


@patch("snowflake_connection.subprocess.run")
def test_uses_explicitly_named_connection_over_default(mock_run):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)

    conn = resolve_and_confirm_snow_connection(
        connection_name="other", config_file=None, assume_yes=True
    )

    assert conn.connection_name == "other"
    assert conn.account == "OTHER-ACC"
    assert conn.parameters.get("private_key_file") is None


@patch("snowflake_connection.subprocess.run")
def test_config_file_passed_as_global_arg(mock_run):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)

    resolve_and_confirm_snow_connection(
        connection_name="ci", config_file="/tmp/config.toml", assume_yes=True
    )

    args = mock_run.call_args.args[0]
    assert args[:3] == ["snow", "--config-file", "/tmp/config.toml"]


@patch("snowflake_connection.subprocess.run")
def test_no_default_connection_exits(mock_run):
    mock_run.return_value = _mock_snow_result(
        [{"connection_name": "other", "is_default": False, "parameters": {"account": "X"}}]
    )

    with pytest.raises(SystemExit) as exc:
        resolve_and_confirm_snow_connection(
            connection_name=None, config_file=None, assume_yes=True
        )
    assert exc.value.code == 1


@patch("snowflake_connection.subprocess.run")
def test_snow_failure_prints_its_error_instead_of_a_traceback(mock_run, capsys):
    mock_run.side_effect = subprocess.CalledProcessError(
        2, ["snow"], output="", stderr="Error: Could not read config file\n"
    )

    with pytest.raises(SystemExit) as exc:
        resolve_and_confirm_snow_connection(
            connection_name="ci", config_file="./config.toml", assume_yes=True
        )

    assert exc.value.code == 1
    err = capsys.readouterr().err
    assert "`snow connection list --config-file ./config.toml` failed (exit 2)" in err
    assert "Could not read config file" in err


@patch("snowflake_connection.subprocess.run")
def test_named_connection_not_found_exits(mock_run):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)

    with pytest.raises(SystemExit) as exc:
        resolve_and_confirm_snow_connection(
            connection_name="does-not-exist", config_file=None, assume_yes=True
        )
    assert exc.value.code == 1


@patch("snowflake_connection.subprocess.run")
def test_missing_connection_error_lists_known_names(mock_run, capsys):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)

    with pytest.raises(SystemExit):
        resolve_and_confirm_snow_connection(
            connection_name="does-not-exist", config_file=None, assume_yes=True
        )

    err = capsys.readouterr().err
    assert "ci" in err and "other" in err


@patch("snowflake_connection.subprocess.run")
def test_connection_without_account_reports_that_not_not_found(mock_run, capsys):
    # A connection that exists but defines no account sends you looking in a
    # different place from one that isn't there at all - the two must not
    # share a "not found" message.
    mock_run.return_value = _mock_snow_result(
        [{"connection_name": "broken", "is_default": True, "parameters": {"user": "x"}}]
    )

    with pytest.raises(SystemExit) as exc:
        resolve_and_confirm_snow_connection(
            connection_name="broken", config_file=None, assume_yes=True
        )

    assert exc.value.code == 1
    err = capsys.readouterr().err
    assert "no account" in err
    assert "No connection named" not in err


@patch("snowflake_connection.subprocess.run")
def test_assume_yes_skips_prompt(mock_run, monkeypatch):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)
    called = False

    def fail_if_called(*_args, **_kwargs):
        nonlocal called
        called = True
        return "y"

    monkeypatch.setattr("builtins.input", fail_if_called)

    resolve_and_confirm_snow_connection(
        connection_name="ci", config_file=None, assume_yes=True
    )

    assert called is False


@patch("snowflake_connection.subprocess.run")
def test_interactive_confirm_yes_proceeds(mock_run, monkeypatch):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)
    monkeypatch.setattr("sys.stdin.isatty", lambda: True)
    monkeypatch.setattr("builtins.input", lambda _prompt: "y")

    conn = resolve_and_confirm_snow_connection(
        connection_name="ci", config_file=None, assume_yes=False
    )

    assert conn.connection_name == "ci"


@patch("snowflake_connection.subprocess.run")
def test_interactive_confirm_no_aborts(mock_run, monkeypatch):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)
    monkeypatch.setattr("sys.stdin.isatty", lambda: True)
    monkeypatch.setattr("builtins.input", lambda _prompt: "n")

    with pytest.raises(SystemExit) as exc:
        resolve_and_confirm_snow_connection(
            connection_name="ci", config_file=None, assume_yes=False
        )
    assert exc.value.code == 1


@patch("snowflake_connection.subprocess.run")
def test_non_interactive_without_yes_exits(mock_run, monkeypatch):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)
    monkeypatch.setattr("sys.stdin.isatty", lambda: False)

    with pytest.raises(SystemExit) as exc:
        resolve_and_confirm_snow_connection(
            connection_name="ci", config_file=None, assume_yes=False
        )
    assert exc.value.code == 1


@patch("snowflake_connection.subprocess.run")
def test_extra_lines_do_not_affect_returned_connection(mock_run, capsys):
    mock_run.return_value = _mock_snow_result(CONNECTIONS)

    resolve_and_confirm_snow_connection(
        connection_name="ci",
        config_file=None,
        assume_yes=True,
        extra_lines=[("Action", "Do the thing")],
    )

    captured = capsys.readouterr()
    assert "Action" in captured.err
    assert "Do the thing" in captured.err
