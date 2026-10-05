"""Shared configuration for the deployment behaviour contract suite.

See README.md in this directory for what the suite is and how to re-record.
"""

import os
import shutil
import subprocess

import pytest

from harness import HELM_VERSION, helm_binary


def pytest_addoption(parser):
    parser.addoption(
        "--update-golden",
        action="store_true",
        default=False,
        help=(
            "Re-record every golden render from the current chart, then skip "
            "the comparisons. Read the resulting diff before committing it."
        ),
    )


def _local_helm_version() -> str:
    result = subprocess.run(
        [helm_binary(), "version", "--short"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return f"unknown ({result.stderr.strip() or 'helm version failed'})"
    return result.stdout.strip()


def _is_pinned_version(version: str) -> bool:
    return version.startswith(f"v{HELM_VERSION}")


def pytest_configure(config):
    helm = helm_binary()
    if shutil.which(helm) is None and not os.path.isfile(helm):
        pytest.exit(
            f"helm not found as {helm!r}. Install Helm {HELM_VERSION}, or point "
            f"HELM_BIN at a {HELM_VERSION} binary — the goldens in this suite "
            f"were recorded with {HELM_VERSION} and another version may render "
            f"differently."
        )

    config.contract_helm_version = _local_helm_version()
    if _is_pinned_version(config.contract_helm_version):
        return

    # Re-recording is the one operation that decides what every later run is
    # compared against, so a version mismatch stops it rather than warning.
    if config.getoption("--update-golden"):
        pytest.exit(
            f"refusing to re-record the goldens with Helm "
            f"{config.contract_helm_version}. They are recorded with "
            f"{HELM_VERSION}, the version the deployer image ships, and "
            f"re-recording with anything else bakes that version's output into "
            f"the baseline. Point HELM_BIN at a {HELM_VERSION} binary. If you "
            f"are deliberately moving the pin, change HELM_VERSION in "
            f"tests/contract/harness.py first and send that change on its own.",
            returncode=1,
        )


def pytest_report_header(config):
    """Report the Helm version in the session header.

    The header is written before the tests run and is not captured, so it is
    visible on a passing run. A warning printed from a fixture is not.
    """
    version = getattr(config, "contract_helm_version", None)
    if version is None:
        return None
    if _is_pinned_version(version):
        return f"contract suite: helm {version}, matching the recorded goldens"
    return (
        f"contract suite: helm {version}, but the goldens were recorded with "
        f"{HELM_VERSION} — the version the deployer image ships. A render diff "
        f"may be the Helm version rather than a chart change. See "
        f"tests/contract/README.md."
    )


@pytest.fixture(scope="session")
def update_golden(request):
    return request.config.getoption("--update-golden")
