# Repository administration checklist

These settings require a repository owner and are not changed by the Stage 0 scaffold.

## Review-rule prerequisite

`CODEOWNERS` currently names only `@bellwerk`, which is also the author of the Stage 0 pull request. An author cannot supply an independent approval or satisfy a required owner review for their own change.

Do not enable a required approval or required CODEOWNERS review until a second trusted GitHub user or team with repository access is configured. Enabling both requirements before that prerequisite is met can make ordinary pull requests impossible to merge without an administrator bypass. Record the intended second reviewer/team before activating either rule.

## Required `main` branch rules

- Require pull requests.
- Once a second trusted reviewer is configured, require at least one approving review, dismiss stale approvals after new commits, and require CODEOWNERS review where a matching owner is available.
- Require the `quality / validate` and `quality / database-smoke` status checks.
- Require branches to be up to date before merge.
- Require conversation resolution.
- Block force pushes and branch deletion.
- Restrict direct pushes and bypasses to emergency administrators.
- Enable secret scanning, push protection, Dependabot alerts, and private vulnerability reporting where the repository plan supports them.

Record any exception with an owner, reason, expiry, and follow-up issue.
