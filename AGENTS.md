# AGENTS.md

## Sources of truth

| Source | Governs |
|--------|---------|
| `README.md` | Supported installation paths, dependencies, compositor support, and user-facing setup |
| `install/install.sh` and `install/modules/` | Installation, migration, deployment, service, and configuration behavior |
| `src/quickshell/` | Runtime UI and Quickshell behavior |
| `src/scripts/` | Runtime shell helpers and system integration |
| `compositors/` | Compositor-specific configuration shipped to users |
| `.dev/architecture/index.yaml` | Selective map of subsystem boundaries and flows; code remains authoritative |

## Architecture and boundaries

- Start architectural navigation at `.dev/architecture/index.yaml`; if its non-exhaustive map does not cover a task, inspect the code directly.
- Keep compositor-specific behavior under `compositors/<compositor>/`; shared Quickshell UI belongs under `src/quickshell/`.
- English is the runtime translation fallback; keep fallback keys in `src/assets/languages/en.json` when changing translatable UI — source: `src/scripts/i18n.sh`.

## Canonical commands

| Command | Use when |
|---------|----------|
| `bash install/install.sh` | Exercise the interactive installer; it changes user configuration and services |
| `SERPANTINUM_DIR="$PWD/src" bin/serpantinumd` | Launch the checkout's runtime rather than an installed copy |
| `python .dev/architecture/tools/validate.py --strict --repo .` | Validate `.dev/architecture/` against its schema and repository evidence |
| `python -m pytest .dev/architecture/tools/tests` | Validate the architecture tooling itself |

## Stateful or external operations

| Operation | Effect / risk | Guardrail |
|-----------|---------------|-----------|
| `bash install/install.sh` | Installs packages, migrates configuration, deploys files, and manages user services | Read the affected module in `install/modules/` first; do not use installer execution as a harmless validation step |
| `bin/serpantinumd` | Starts or controls the live desktop shell | Set `SERPANTINUM_DIR` to the checkout when validating local code |

## Gotchas

- `bin/serpantinumd` otherwise derives `SERPANTINUM_DIR` relative to `bin/`; installed and checkout layouts can therefore exercise different files.
- The architecture map is deliberately non-exhaustive; absence from `.dev/architecture/` is not evidence that a capability is absent.
