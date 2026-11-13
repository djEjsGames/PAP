# PAP browser test deployment

This branch contains exported browser assets only. The repository main branch is unchanged.

- `/PAP/`: preserved existing PC build
- `/PAP/mobile/`: portrait mobile test build

Update mobile assets with the mobile worktree tool `tools/export_web_mobile.ps1`, copy its output into `mobile/`, and push this branch to publish. This branch does not run the full game regression suite. A later deployment from main replaces the Pages artifact; republish this branch to restore the mobile route. Native Android behavior and browser handling feel require user testing.
