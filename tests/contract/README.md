# Deployment behaviour contract

This suite records what the runner chart renders for a set of representative
customer configurations and fails when a change alters it. A change to the
render appears as a diff in the pull request that caused it, for the reviewer to
confirm or reject.

## How this differs from `tests/helm/`

| | `tests/helm/` | `tests/contract/` |
|---|---|---|
| Question | is this field right? | did anything change? |
| Golden holds | a single Kubernetes resource | the whole render |
| Fails when | a specific property is wrong | anything at all moves |

The two suites answer different questions and are maintained separately.

## Layout

```
tests/contract/
  README.md               this file
  conftest.py             helm presence + version check, --update-golden option
  harness.py              rendering and canonicalisation
  test_chart_render.py    the golden comparison and the named assertions
  fixtures/               chart values, with literal synthetic credentials
  golden/                 recorded renders, canonicalised
```

## Running it

```bash
pytest tests/contract -v
```

Requires `pytest`, `pyyaml` and a `helm` binary. If the `helm` on your PATH is
not the pinned version, point `HELM_BIN` at one that is:

```bash
HELM_BIN=/path/to/helm-3.16.3 pytest tests/contract -v
```

The suite reports the Helm version in its session header, so a version mismatch
is distinguishable from a genuine render diff. It is a header rather than a
warning printed during the run because pytest captures the latter and shows it
only on failure, which hides it exactly when every test passes.

## Helm version

The goldens are recorded with the Helm version used by the deployer image,
currently `3.16.3` (`HELM_VERSION` in `build-container/Dockerfile`, in
`matillion/agent-deployment-poc`). That is the version that renders this chart
into customer clusters. CI (`.github/workflows/test.yml`) is pinned to the same
version, and the two have to move together.

A Helm version change re-records every golden at once and produces a diff nobody
can usefully review. Change the pinned version on its own, in a pull request
containing nothing else.

## Canonicalisation

Three rules:

1. Fixed release name, `matillion-runner`, so generated names are stable.
2. Documents sorted by `(kind, metadata.name)`.
3. Mapping keys sorted recursively.

Each rule removes something this suite would otherwise catch, so a fourth needs
a demonstrated false positive behind it.

Nothing else needs normalising: the chart templates contain no non-deterministic
constructs — no `randAlphaNum`, `uuidv4`, `now`, `Release.Time`, checksum
annotations or certificate generation. If that changes, fix the template.

## Fixtures

| Fixture | What it covers |
|---|---|
| `aws-eks-minimal` | One runner, no autoscaling, IRSA, network policy enabled. |
| `aws-eks-scaling` | HPA, zone spread, disruption budget, health probes, tenant labels. |

Between them they exercise the templates that render conditionally, which are
the ones a change is most likely to disturb unnoticed.

Fixture credentials are literal and synthetic: `fixture-not-a-real-secret`,
`arn:aws:iam::000000000000:role/fixture-not-a-real-role`. Do not use `${ENV}`
placeholders, as `runner/helm/runner/test-values.yaml` does. This repository is
mirrored publicly and runs gitleaks, so fixture values need to be recognisably
fake on sight.

Azure and GCP fixtures land with M2 and M3. One thing to know before starting
them: `harness.py` identifies the runner container by the image substring
`etl-agent`, which is AWS-only. Azure renders `matillion.azurecr.io/cloud-agent`
and GCP renders `maia-runner`, so four of the five named assertions fail with
"no runner container" on a fixture for either. The chart is fine — every
asserted property holds on both renders. Match on the container name instead,
which is `<fullname>-pods` on all three clouds, and exclude the script runner,
whose container follows the same pattern under a different fullname.

ECS and Container Apps are out of scope here. They do not use the chart, so they
belong with the Terraform assertions rather than this suite.

### Lint scope

The goldens are PyYAML output, and its sequence indentation does not satisfy the
repository's `.yamllint.yml`. This does not matter today, as `helm-test.yml` runs
yamllint over `runner/helm/` only. If yamllint is widened to the whole
repository, exclude `tests/contract/golden/`. Hand-formatting a recorded file
would make `--update-golden` produce spurious diffs on every run.

## Re-recording a golden

```bash
pytest tests/contract --update-golden
```

Re-recording with any Helm version other than the pinned one is refused, because
it is the one operation that decides what every later run is compared against.
To move the pin deliberately, change `HELM_VERSION` in `harness.py` first and
send that change on its own.

Read the resulting diff before committing it. Re-recording takes one command and
approves a change to every deployment matching that fixture. The named
assertions below are unaffected by `--update-golden` and stay in force when a
golden is re-recorded.

If a fixture's render grows beyond what a reviewer will read, split the fixture.
A diff approved unread provides no protection.

## The named assertions

The golden comparison catches any change, including ones nobody anticipated, but
reports them all the same way. Properties with a known, silent failure mode
therefore get a dedicated test that fails with a stated reason.

| Assertion | What breaks without it |
|---|---|
| `imagePullPolicy` is `Always` | Runner updates work by restarting and re-resolving the tag. Under `IfNotPresent` the restart reuses the node's cached image and updates stop, with no error and no event. |
| Runner image is a tag, never a digest | The same failure by another route. A digest is immutable, so re-resolving it cannot pick up a new build. |
| `terminationGracePeriodSeconds` ≥ 43200 | The runner drains on a schedule matched to its own `agent.shutdown.timeout`. A shorter window SIGKILLs it mid-task on drain or rolling update, failing in-flight pipeline work. |
| The client secret appears exactly once, in the `stringData` of `<release>-config` | A refactor moving it to a ConfigMap would store a credential unencrypted and read as a formatting change in the golden. See below for why "exactly once". |
| A `NetworkPolicy` with `Egress` selects the runner pods | Disabling it removes egress restriction from a workload holding cloud credentials, and renders as one resource disappearing from the output. |

### Why the secret assertion is "exactly once" and not "only in a Secret"

A planned change stops the chart receiving the secret value at all. "The secret
appears only in a Secret" is trivially true of a render containing no secret, so
that form of the assertion would pass permanently once the change lands, without
signalling that it had stopped testing anything.

Requiring exactly one occurrence in a named location covers both cases: a
refactor that moves or duplicates the credential today, and the planned change
tomorrow. The second will fail the test, which is intended — the assertion needs
a decision at that point.

Its failure message says what to do: change it to require zero occurrences
rather than delete it.

## Adding to this suite

When a review finds that the golden caught something significant, add a named
assertion for it. The named assertions are the primary protection; the golden
covers what they do not.
