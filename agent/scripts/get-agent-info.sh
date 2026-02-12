#!/usr/bin/env bash
#
# get-agent-info.sh
#
# Finds the Matillion agent deployment and displays
# the service account and associated cloud role/identity.
#
# Prerequisites: kubectl configured with access to the target cluster.
#
# Usage:
#   ./get-agent-info.sh                        # scans all namespaces
#   ./get-agent-info.sh -n <namespace>         # target a specific namespace

set -euo pipefail

NAMESPACE_FLAG=("--all-namespaces")
NAMESPACE=""

while getopts "n:" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG"; NAMESPACE_FLAG=("-n" "$NAMESPACE") ;;
    *) echo "Usage: $0 [-n namespace]"; exit 1 ;;
  esac
done

echo "Looking for Matillion agent deployments..."
echo

# Find deployments by the helm chart label
DEPLOYMENTS=$(kubectl get deployments "${NAMESPACE_FLAG[@]}" \
  -l "app.kubernetes.io/name=matillion-agent" \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.template.spec.serviceAccountName}{"\n"}{end}' 2>/dev/null)

if [[ -z "$DEPLOYMENTS" ]]; then
  echo "No Matillion agent deployments found."
  echo "Hint: check you have the right kubeconfig context and namespace."
  exit 1
fi

while IFS=$'\t' read -r ns deploy sa; do
  [[ -z "$deploy" ]] && continue

  echo "Deployment:       $ns/$deploy"
  echo "Service Account:  $sa"

  # Fetch the service account annotations
  ANNOTATIONS=$(kubectl get serviceaccount "$sa" -n "$ns" \
    -o jsonpath='{.metadata.annotations}' 2>/dev/null || true)

  # AWS — EKS IRSA role ARN
  ROLE_ARN=$(kubectl get serviceaccount "$sa" -n "$ns" \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || true)

  # Azure — Workload Identity client ID
  WI_CLIENT_ID=$(kubectl get serviceaccount "$sa" -n "$ns" \
    -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' 2>/dev/null || true)

  # GCP — Workload Identity GSA
  GCP_SA=$(kubectl get serviceaccount "$sa" -n "$ns" \
    -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null || true)

  if [[ -n "$ROLE_ARN" ]]; then
    echo "Cloud Provider:   AWS"
    echo "IAM Role ARN:     $ROLE_ARN"
  elif [[ -n "$WI_CLIENT_ID" ]]; then
    echo "Cloud Provider:   Azure"
    echo "Workload ID:      $WI_CLIENT_ID"
  elif [[ -n "$GCP_SA" ]]; then
    echo "Cloud Provider:   GCP"
    echo "GCP SA:           $GCP_SA"
  else
    echo "Cloud Role/ID:    (none found — may be using local/static credentials)"
  fi

  echo "---"
done <<< "$DEPLOYMENTS"
