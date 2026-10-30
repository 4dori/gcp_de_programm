# Orchestration and CI/CD

## Responsibilities

- **Cloud Build:** validate and deploy infrastructure, PySpark scripts, and the Workflows definition when code changes.
- **Cloud Workflows:** run the four Dataproc batches in dependency order, poll for completion, and stop on failure. It runs data jobs; it does not deploy code.

Keep these paths separate: a source-code push should not automatically launch a full data refresh.

## Case 1: Mentoring / single project (recommended first)

- Cloud Build on pull requests: run `terraform fmt`, `terraform validate`, and a plan; do not apply infrastructure.
- Cloud Build on merge to `main`: publish versioned job artifacts and deploy/update `mentoring-pipeline`.
- Apply Terraform manually or through an explicitly approved release step.
- Start Workflows manually after checking inputs and costs; add a schedule later if useful.

**Why:** simple to teach, easy to debug, and avoids accidental database/network changes or Dataproc charges on every push.

## Case 2: Production / repeatable operations

- Pull requests run validation and plan checks.
- Merges publish immutable, commit-tagged artifacts. A protected deployment trigger applies reviewed Terraform changes and deploys Workflows, with approval for infrastructure changes.
- Cloud Scheduler starts Workflows on a schedule, or an event trigger starts them when source data is ready.
- Workflows submits and monitors Dataproc batches, reports failures, and uses retries only for transient errors.

**Why:** deployments are auditable and data runs are independent of code releases. Add alerts, run identifiers, and idempotency controls before unattended production runs.

## Recommendation

Start with Case 1. Keep Cloud Build responsible for validation/deployment and invoke the existing Workflow manually. After the lane is stable, add a Scheduler trigger and the Case 2 release controls. Avoid automatic `terraform apply` on every push, especially while Terraform manages Cloud SQL and paid NAT resources.
