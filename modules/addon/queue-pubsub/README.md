# addon/queue-pubsub (GCP) — NOT YET IMPLEMENTED

**Disabled on the roadmap.** A Google Cloud Pub/Sub-backed pipeline-trigger
add-on for GCP agent deployments is planned but **not yet implemented**. This
directory is an intentional stub so the composer catalog can reference the path
without provisioning anything.

There are deliberately **no Terraform resources** here. The composer must treat
`addon/queue-pubsub` as unavailable and fall back to
[`addon/queue-sdk`](../queue-sdk) (SDK polling) for GCP deployments until the
Pub/Sub adapter lands.

Planned shape (for reference only — subject to change):
- `trigger_topic` — `google_pubsub_topic`
- `trigger_subscription` — `google_pubsub_subscription` (with dead-letter topic)
- `trigger_adapter` — Cloud Run / Cloud Function consumer, ordered after the
  agent service
- Least-privilege: `pubsub.subscriptions.consume`, `pubsub.messages.ack`

Tracking: epic DPC-52404 (Modular Agent Deployment composer).
