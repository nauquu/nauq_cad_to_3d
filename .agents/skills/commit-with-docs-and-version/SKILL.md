---
name: commit-with-docs-and-version
description: Standard commit workflow with versioning and comprehensive documentation updates across all docs files for NAUQ CAD to 3D.
---

# Commit Workflow

Whenever a commit is requested, execute the following 4-step workflow:

1. **Bump Version (SemVer):**
   - Update `PLUGIN_VERSION` in `nauq_cad_to_3d.rb` following Semantic Versioning (`MAJOR.MINOR.PATCH`).

2. **Audit & Synchronize All Relevant Documentation (`docs/`):**
   - **`docs/CHANGELOG.md`** *(Mandatory)*: Add new version release notes with date and structured categories (`Added`, `Changed`, `Fixed`, `Removed`).
   - **`docs/PROJECT_MAP.md`**: Update if files/modules were added, deleted, or their responsibilities changed.
   - **`docs/API_CONTRACT.md`**: Update if method signatures, options, or data schemas were introduced or modified.
   - **`docs/ARCHITECTURE.md`**: Update if pipeline flows, coordinate systems, or architectural decisions were updated.
   - **`docs/MODULE_RULES.md` & `README.md`**: Update if new constraints, conventions, or user workflows were introduced.

3. **Build & Sync RBZ Package:**
   - Run `build_rbz.ps1` (via PowerShell) to package and sync the new Trimble-compliant `.rbz` to SketchUp plugins directory.

4. **Git Commit:**
   - Stage all changes with `git add .` (or `git add/rm`).
   - Execute `git commit -m "<type>(<scope>): <message>"` using Conventional Commits standard.
