---
name: commit-with-docs-and-version
description: Standard commit workflow with versioning and documentation updates for NAUQ CAD to 3D.
---

# Commit Workflow

1. Update `PLUGIN_VERSION` in `nauq_cad_to_3d.rb`.
2. Update `CHANGELOG.md` with release notes and date.
3. Run `build_rbz.ps1` to produce the new `.rbz` package.
4. Execute `git add .` and `git commit -m "<type>(<scope>): <message>"`.
