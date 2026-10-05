"""Deployment behaviour contract — chart render assertions.

Two kinds of test:

  * One golden comparison per fixture. It catches any change to the render but
    reports them all the same way, and one command silences it.
  * One named assertion per known silent failure mode. Each fails with a stated
    reason, and none can be silenced by --update-golden.

When a review finds that the golden caught something significant, add a named
assertion for it here.
"""

import difflib

import pytest

from harness import (
    MIN_TERMINATION_GRACE_SECONDS,
    RELEASE,
    contains_value,
    documents,
    fixture_names,
    fixture_values,
    golden_path,
    render,
    resource_id,
    runner_containers,
)

FIXTURES = fixture_names()


def _diff(name: str, expected: str, actual: str) -> str:
    lines = difflib.unified_diff(
        expected.splitlines(keepends=True),
        actual.splitlines(keepends=True),
        fromfile=f"golden/{name}.yaml (recorded)",
        tofile=f"golden/{name}.yaml (rendered now)",
    )
    return "".join(lines)


def test_fixtures_are_present():
    """A suite that runs with no fixtures passes, which is indistinguishable
    from one that is not running at all."""
    assert FIXTURES, (
        "no fixtures found in tests/contract/fixtures/. Every other test in "
        "this module is parametrised over that directory, so the whole suite "
        "would pass without rendering anything."
    )


# --------------------------------------------------------------------------
# Golden comparison
# --------------------------------------------------------------------------


@pytest.mark.parametrize("name", FIXTURES)
def test_render_matches_golden(name, update_golden):
    """The rendered deployment is unchanged from what was last reviewed.

    A failure here is not necessarily a defect. It requires the author to
    confirm that the resulting change to every deployment using this chart is
    intended.
    """
    rendered = render(name)
    golden = golden_path(name)

    if update_golden:
        golden.parent.mkdir(parents=True, exist_ok=True)
        golden.write_text(rendered)
        pytest.skip(f"golden re-recorded: {name}")

    assert golden.exists(), (
        f"no golden recorded for fixture {name!r}. Record it with "
        f"`pytest tests/contract --update-golden` and read the result before "
        f"committing it."
    )

    expected = golden.read_text()
    assert rendered == expected, (
        f"the render of fixture {name!r} has changed. Every deployment using "
        f"this configuration changes with it. Review the diff below; if it is "
        f"intended, re-record with `pytest tests/contract --update-golden`.\n\n"
        + _diff(name, expected, rendered)
    )


# --------------------------------------------------------------------------
# Named assertions, one per known silent failure mode
# --------------------------------------------------------------------------


@pytest.mark.parametrize("name", FIXTURES)
def test_runner_image_pull_policy_is_always(name):
    """Runner updates work by restarting the container and
    re-resolving the tag. Under IfNotPresent the restart reuses the cached
    image on the node and updates stop — with no error, no event and no
    difference in the rendered manifest that reads as a problem."""
    containers = runner_containers(documents(name))
    assert containers, f"no runner container in the render of {name!r}"

    for doc, _spec, container in containers:
        policy = container.get("imagePullPolicy")
        assert policy == "Always", (
            f"{resource_id(doc)} container {container.get('name')!r} has "
            f"imagePullPolicy {policy!r}, not 'Always'. Under {policy!r} a "
            f"restart reuses the node's cached image, so runner updates stop "
            f"being delivered without any visible failure."
        )


@pytest.mark.parametrize("name", FIXTURES)
def test_runner_image_is_a_mutable_tag(name):
    """The same failure as the previous test, by a different route. A digest
    reference is immutable, so re-resolving it on restart cannot pick up a new
    runner build."""
    containers = runner_containers(documents(name))
    assert containers, f"no runner container in the render of {name!r}"

    for doc, _spec, container in containers:
        image = container["image"]
        assert "@sha256:" not in image, (
            f"{resource_id(doc)} pins the runner by digest: {image}. A digest "
            f"is immutable, so restarting the container can never pick up a "
            f"new runner build and updates silently stop. Use a "
            f"mutable tag."
        )


@pytest.mark.parametrize("name", FIXTURES)
def test_termination_grace_period_is_not_reduced(name):
    """The runner drains on a schedule matched to its own
    agent.shutdown.timeout. Shortening the window means node drains and rolling
    updates SIGKILL runners mid-task, failing the in-flight pipeline work."""
    workloads = {
        resource_id(doc): (doc, spec)
        for doc, spec, _container in runner_containers(documents(name))
    }
    assert workloads, f"no runner container in the render of {name!r}"

    for doc, spec in workloads.values():
        grace = spec.get("terminationGracePeriodSeconds")
        assert grace is not None, (
            f"{resource_id(doc)} sets no terminationGracePeriodSeconds, so it "
            f"falls back to the Kubernetes default of 30s. In-flight pipeline "
            f"work is truncated on any drain or rolling update."
        )
        assert grace >= MIN_TERMINATION_GRACE_SECONDS, (
            f"{resource_id(doc)} has terminationGracePeriodSeconds {grace}, "
            f"below the required {MIN_TERMINATION_GRACE_SECONDS}. The runner "
            f"needs the full window to drain in-flight pipeline tasks; a "
            f"shorter one SIGKILLs it mid-task on drain or rolling update."
        )


@pytest.mark.parametrize("name", FIXTURES)
def test_client_secret_appears_exactly_once_in_the_config_secret(name):
    """The OAuth client secret must appear exactly once in the whole render, in
    the stringData of the <release>-config Secret, and nowhere else.

    The weaker form, "only in a Secret", passes trivially on a render containing
    no secret at all. A planned change stops the chart receiving the secret
    value, at which point that form would pass permanently without signalling
    that it had stopped testing anything. Requiring exactly one occurrence in a
    named location covers both a refactor that moves or duplicates the
    credential today and the planned change tomorrow. The second fails this
    test, which is intended: the assertion needs a decision at that point.
    """
    secret_value = fixture_values(name).get("config", {}).get("oauthClientSecret")
    assert secret_value, (
        f"fixture {name!r} sets no config.oauthClientSecret, so this assertion "
        f"would pass vacuously. Give the fixture a sentinel value."
    )

    carriers = [doc for doc in documents(name) if contains_value(doc, secret_value)]

    assert carriers, (
        f"the chart no longer renders the client secret anywhere — the "
        f"sentinel from fixture {name!r} does not appear in the render.\n\n"
        f"If this is the planned change landing (the chart stops receiving the secret "
        f"value at all), change this assertion to require ZERO occurrences. Do "
        f"not delete it: without it, nothing notices a credential reappearing "
        f"in the render later.\n\n"
        f"If that change has not landed, the runner has stopped being given its "
        f"credential and will fail to authenticate."
    )

    assert len(carriers) == 1, (
        f"the client secret appears in {len(carriers)} resources — "
        f"{', '.join(resource_id(d) for d in carriers)} — and must appear in "
        f"exactly one. Each extra copy is a credential stored somewhere nobody "
        f"is rotating or auditing."
    )

    carrier = carriers[0]
    assert carrier.get("kind") == "Secret", (
        f"the client secret is rendered into {resource_id(carrier)}, which is "
        f"not a Secret. A credential outside a Secret is stored unencrypted, is "
        f"readable by anything that can read that resource kind, and shows up "
        f"in `kubectl get -o yaml` output and support bundles."
    )

    expected_name = f"{RELEASE}-config"
    assert carrier["metadata"]["name"] == expected_name, (
        f"the client secret is rendered into Secret "
        f"{carrier['metadata']['name']!r}, not {expected_name!r}. The runner "
        f"Deployment mounts and envFroms that name; a credential in a "
        f"differently-named Secret is either unused or reaching somewhere it "
        f"was not meant to."
    )

    assert contains_value(carrier.get("stringData") or {}, secret_value), (
        f"the client secret is in {resource_id(carrier)} but not in its "
        f"stringData. It has moved to another field — check it has not been "
        f"put somewhere that is not treated as secret data."
    )


@pytest.mark.parametrize("name", FIXTURES)
def test_network_policy_restricts_the_runner(name):
    """The runner pod holds cloud credentials. Disabling the NetworkPolicy
    removes egress restriction from that workload, and shows up in the golden as
    one resource missing from the output."""
    docs = documents(name)
    policies = [doc for doc in docs if doc.get("kind") == "NetworkPolicy"]
    assert policies, (
        f"fixture {name!r} renders no NetworkPolicy. The runner pod holds "
        f"cloud credentials and must not have unrestricted egress — set "
        f"networkPolicy.enabled=true."
    )

    workloads = {
        resource_id(doc): doc["spec"]["template"]["metadata"].get("labels", {})
        for doc, _spec, _container in runner_containers(docs)
    }
    assert workloads, f"no runner workload in the render of {name!r}"

    for workload_id, labels in workloads.items():
        assert labels, (
            f"{workload_id} renders no pod labels, so no NetworkPolicy can "
            f"select it and its egress is unrestricted."
        )

        matched = [
            policy
            for policy in policies
            if _selector_matches(
                policy.get("spec", {}).get("podSelector", {}), labels
            )
        ]
        assert matched, (
            f"{workload_id} is selected by none of the {len(policies)} "
            f"NetworkPolicy resource(s) in fixture {name!r} (its pod labels "
            f"are {labels}). Its egress is unrestricted."
        )

        for policy in matched:
            policy_types = policy.get("spec", {}).get("policyTypes", [])
            assert "Egress" in policy_types, (
                f"{resource_id(policy)} selects {workload_id} but has "
                f"policyTypes {policy_types}, which does not include Egress. A "
                f"workload holding cloud credentials is left able to reach "
                f"anything."
            )


def _selector_matches(pod_selector: dict, labels: dict) -> bool:
    """Whether a NetworkPolicy podSelector selects a pod carrying these labels.

    An empty podSelector selects every pod in the namespace, which includes the
    runner.
    """
    if pod_selector.get("matchExpressions"):
        raise AssertionError(
            f"a NetworkPolicy podSelector uses matchExpressions "
            f"({pod_selector['matchExpressions']}), which this suite does not "
            f"evaluate, so it cannot tell whether the policy selects the runner "
            f"pods. Extend _selector_matches to handle them. Do not assume the "
            f"policy matches: treating an unevaluated selector as a match is "
            f"how this assertion passes while the runner has unrestricted "
            f"egress."
        )
    match_labels = pod_selector.get("matchLabels") or {}
    if not match_labels:
        return True
    return all(labels.get(k) == v for k, v in match_labels.items())
