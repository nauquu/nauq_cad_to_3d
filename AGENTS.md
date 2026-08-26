# AGENTS.md

## Repository Workflow Guidelines

- **Git Commits**: DO NOT run `git commit` automatically unless the user explicitly requests to commit.
- **Commit Skill Enforcement**: Whenever the user requests to commit, ALWAYS strictly follow the `commit-with-docs-and-version` workflow:
  1. Bump `PLUGIN_VERSION` in `nauq_cad_to_3d.rb` (SemVer).
  2. Audit and synchronize **all relevant documentation** in `docs/` (`CHANGELOG.md`, `PROJECT_MAP.md`, `API_CONTRACT.md`, `ARCHITECTURE.md`, `MODULE_RULES.md`, and `README.md` if affected).
  3. Run `build_rbz.ps1` to produce and sync the new Trimble-compliant `.rbz` package.
  4. Execute `git add .` and `git commit -m "<type>(<scope>): <message>"`.
- **Documentation**: Keep docs, comments, and specs accurate and synchronized with the latest codebase.
- **Trimble / Extension Warehouse Standard**: Ensure `.rbz` packages are always Trimble-compliant (root contains `nauq_cad_to_3d.rb` loader and `nauq_cad_to_3d/` subfolder).
- **SemVer**: Maintain Semantic Versioning (`MAJOR.MINOR.PATCH`).
