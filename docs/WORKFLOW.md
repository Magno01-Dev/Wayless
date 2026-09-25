# WAYLESS Git Workflow

## Branches
- `main`: approved/release-ready baseline only.
- `develop`: integration branch for work that has passed its local implementation checks but is not yet released.
- `feature/<trello-card>-<slug>`: isolated feature/fix work.
- `hotfix/<slug>`: urgent fixes branched from the appropriate approved baseline.

## Change flow
1. Start from the correct baseline and Trello card.
2. Create a feature/fix branch.
3. Make the smallest scoped change.
4. Open PR with affected Place/service/files, dependencies and QA steps.
5. Run in-game QA.
6. Only after PASS/owner approval, merge/promote and update Drive control docs/Trello.

## Source-of-truth split
- GitHub: code history, branches, diffs, PRs, rollback.
- Google Drive: project control docs, approved packages/backups, assets and release evidence.
- Trello: work state and ownership.
