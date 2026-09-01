# cv_oci

A Tekton + Cloud Native Buildpacks supply-chain pipeline. Learning + portfolio
artifact. Design of record: `docs/designs/buildpacks-pivot.md` (the sole design
doc — the earlier crane/apko `pipeline-restructure.md` /
`pipeline-gitops-replan.md` were absorbed and deleted in the 2026-09-01 SSOT
merge).

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
