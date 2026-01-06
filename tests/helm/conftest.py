import pytest
import subprocess
import shutil

def pytest_configure(config):
    """Check that required tools are available"""
    if not shutil.which('helm'):
        pytest.exit("Helm is not installed or not in PATH")

@pytest.fixture(scope="session")
def helm_version():
    """Get Helm version for compatibility checks"""
    result = subprocess.run(['helm', 'version', '--short'], 
                          capture_output=True, text=True)
    return result.stdout.strip()