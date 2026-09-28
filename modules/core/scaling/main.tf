# modules/core/scaling
#
# Agent replica bounds / autoscaling policy. Provider-agnostic configuration
# contract: it provisions no cloud resources itself. The compute modules
# (core/compute-ecs, core/compute-container-apps, core/compute-cloud-run) read
# these outputs to set desired/min/max replica counts and to decide whether to
# attach a provider-native autoscaler.

locals {
  # Guard: max must be >= min. Cross-variable validation is not expressible in a
  # single variable block, so it is enforced here.
  _min_le_max = var.max_agents >= var.min_agents ? true : tobool("max_agents must be >= min_agents")

  # Effective desired replica count when autoscaling is disabled.
  desired_agents = var.autoscale ? var.min_agents : var.min_agents
}
