# Repository administration checklist

These settings require a repository owner and are not changed by the Stage 0 scaffold.

## Required `main` branch rules

- Require pull requests and at least one approving review.
- Dismiss stale approvals when new commits are pushed.
- Require CODEOWNERS review where a matching owner is available.
- Require the `quality / validate` status check.
- Require branches to be up to date before merge.
- Require conversation resolution.
- Block force pushes and branch deletion.
- Restrict direct pushes and bypasses to emergency administrators.
- Enable secret scanning, push protection, Dependabot alerts, and private vulnerability reporting where the repository plan supports them.

Record any exception with an owner, reason, expiry, and follow-up issue.
