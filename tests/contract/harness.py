"""Rendering harness for the deployment behaviour contract suite.

Renders the runner chart with a fixture's values and canonicalises the result so
that two renders of an unchanged chart are byte-identical.

Canonicalisation is three rules:

  1. Fixed release name, so generated resource names are stable.
  2. Documents sorted by (kind, metadata.name), so template file order and
     Helm's own ordering cannot churn the golden.
  3. Mapping keys sorted recursively, so a reordered template block is not a
     diff.

Each rule removes something the suite would otherwise catch, so a fourth needs a
demonstrated false positive behind it.

The chart templates contain no non-deterministic constructs — no randAlphaNum,
uuidv4, now, Release.Time, checksum annotations or certificate generation — so
nothing else needs normalising. If that changes, fix the template.
"""

import os
import subprocess
from functools import lru_cache
from pathlib import Path

import yaml

RELEASE = "matillion-runner"

#: The Helm version the goldens are recorded with. It tracks the version pinned
#: in the deployer image that renders this chart into customer clusters
#: (build-container/Dockerfile, HELM_VERSION), and CI is pinned to the same
#: version. See README.md.
HELM_VERSION = "3.16.3"

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
CHART = REPO_ROOT / "runner" / "helm" / "runner"

FIXTURE_DIR = HERE / "fixtures"
GOLDEN_DIR = HERE / "golden"

#: Substring identifying the Matillion runner container's image. Used to tell
#: the runner apart from any sidecar or script-runner container in the render.
RUNNER_IMAGE_MARKER = "etl-agent"

#: The runner does not exit until its in-flight pipeline tasks have completed,
#: and this window is matched to the runner's own agent.shutdown.timeout.
#: Lowering it means a drain or rolling update kills in-flight work.
MIN_TERMINATION_GRACE_SECONDS = 43200

WORKLOAD_KINDS = ("Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob")


def helm_binary() -> str:
    """The helm executable to render with.

    Defaults to whatever `helm` is on PATH. Set HELM_BIN to a Helm
    {HELM_VERSION} binary if your default helm is a different version; the
    goldens are recorded against the version the deployer image ships, and a
    different one can render differently.
    """
    return os.environ.get("HELM_BIN", "helm")


def fixture_names() -> list[str]:
    return sorted(p.stem for p in FIXTURE_DIR.glob("*.yaml"))


def fixture_path(name: str) -> Path:
    return FIXTURE_DIR / f"{name}.yaml"


def golden_path(name: str) -> Path:
    return GOLDEN_DIR / f"{name}.yaml"


def _sort_key(doc: dict) -> tuple:
    try:
        return (doc["kind"], doc["metadata"]["name"])
    except (KeyError, TypeError) as exc:
        raise AssertionError(
            "a rendered document has no kind/metadata.name, so the render "
            f"cannot be ordered deterministically: {doc!r}"
        ) from exc


@lru_cache(maxsize=None)
def render(name: str) -> str:
    """Render one fixture and return the canonicalised YAML."""
    result = subprocess.run(
        [
            helm_binary(),
            "template",
            RELEASE,
            str(CHART),
            "-f",
            str(fixture_path(name)),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"helm template failed for fixture {name!r}:\n{result.stderr.strip()}"
        )
    docs = [d for d in yaml.safe_load_all(result.stdout) if d]
    docs.sort(key=_sort_key)
    return yaml.safe_dump_all(docs, sort_keys=True, default_flow_style=False)


def documents(name: str) -> list[dict]:
    """The rendered documents for a fixture, in canonical order."""
    return [d for d in yaml.safe_load_all(render(name)) if d]


def fixture_values(name: str) -> dict:
    return yaml.safe_load(fixture_path(name).read_text())


def pod_specs(docs: list[dict]) -> list[tuple[dict, dict]]:
    """(document, podSpec) for every workload in the render."""
    out = []
    for doc in docs:
        if doc.get("kind") not in WORKLOAD_KINDS:
            continue
        spec = doc.get("spec", {}).get("template", {}).get("spec")
        if spec:
            out.append((doc, spec))
    return out


def runner_containers(docs: list[dict]) -> list[tuple[dict, dict, dict]]:
    """(document, podSpec, container) for every Matillion runner container."""
    out = []
    for doc, spec in pod_specs(docs):
        for container in spec.get("containers", []):
            if RUNNER_IMAGE_MARKER in container.get("image", ""):
                out.append((doc, spec, container))
    return out


def resource_id(doc: dict) -> str:
    return f"{doc.get('kind')}/{doc.get('metadata', {}).get('name')}"


def contains_value(node, needle: str) -> bool:
    """True if `needle` appears as a string anywhere in a parsed document."""
    if isinstance(node, str):
        return needle in node
    if isinstance(node, dict):
        return any(
            contains_value(k, needle) or contains_value(v, needle)
            for k, v in node.items()
        )
    if isinstance(node, list):
        return any(contains_value(item, needle) for item in node)
    return False
