import importlib.util
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
LIB_DIR = SCRIPTS_DIR / "lib"

for path in (str(SCRIPTS_DIR), str(LIB_DIR)):
    if path not in sys.path:
        sys.path.insert(0, path)


def load_module_from_path(name: str, path: Path):
    """Loads a script with a hyphenated filename (e.g. install-library.py)
    as an importable module - `import install-library` isn't valid Python,
    so tests load it by file path instead.
    """
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module
