#!/bin/bash

# Script to set up branch protection rules for the repository
# This script should be run by a repository administrator

REPO_OWNER="matillion"
REPO_NAME="poc-agent-deployment"
BRANCH="main"

echo "Setting up branch protection for ${REPO_OWNER}/${REPO_NAME}:${BRANCH}"

# Required status checks - these must pass before merging
REQUIRED_CHECKS=(
    "validate"                    # From PR Validation workflow
    "conventional-commits"        # From PR Validation workflow  
    "python-tests"               # From Run Tests workflow
    "helm-tests"                 # From Run Tests workflow
    "integration-tests"          # From Run Tests workflow
    "helm-lint"                  # From Helm Chart Testing workflow
    "yaml-validation"            # From Helm Chart Testing workflow
    "docker-security-scan"       # From Security Scanning workflow
    "helm-security-scan"         # From Security Scanning workflow
    "secrets-scan"               # From Security Scanning workflow
    "dependency-scan"            # From Security Scanning workflow
)

# Convert array to JSON format for GitHub API
CONTEXTS_JSON=$(printf '"%s",' "${REQUIRED_CHECKS[@]}")
CONTEXTS_JSON="[${CONTEXTS_JSON%,}]"

# Create the branch protection rule
gh api \
  --method PUT \
  /repos/${REPO_OWNER}/${REPO_NAME}/branches/${BRANCH}/protection \
  --field required_status_checks="{
    \"strict\": true,
    \"contexts\": ${CONTEXTS_JSON}
  }" \
  --field enforce_admins=true \
  --field required_pull_request_reviews="{
    \"required_approving_review_count\": 1,
    \"dismiss_stale_reviews\": true,
    \"require_code_owner_reviews\": false
  }" \
  --field restrictions=null \
  --field allow_force_pushes=false \
  --field allow_deletions=false

if [ $? -eq 0 ]; then
    echo "✅ Branch protection rules successfully applied to ${BRANCH}"
    echo ""
    echo "The following rules are now enforced:"
    echo "- All status checks must pass before merging"
    echo "- Pull requests require 1 approving review"  
    echo "- Stale reviews are dismissed when new commits are pushed"
    echo "- Force pushes and branch deletions are blocked"
    echo ""
    echo "Required status checks:"
    for check in "${REQUIRED_CHECKS[@]}"; do
        echo "  - $check"
    done
else
    echo "❌ Failed to set up branch protection"
    echo "Make sure you have admin permissions on the repository"
    exit 1
fi