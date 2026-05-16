# Potential Future Improvements

## Replace `dy-*` Aliases With More Reliable Entrypoints

### Problem

Remote agents regularly hit brittle behavior around the `dy-*` aliases defined by
`source dyoainit`. The common failure mode is that alias expansion and shell
state only exist in the initialized interactive shell. Non-interactive SSM
payloads, one-line remote scripts, and shells that are not actually login Bash
can fail to resolve `dy-a`, `dy-r`, or related commands even when the analysis
clone itself is present.

### Option: Install `dy-*` Shell Scripts When `DAYOA` Is Created

Pros:

- Makes commands discoverable through normal `PATH` lookup, so `command -v dy-r`
  works without relying on Bash alias expansion.
- Improves behavior in non-interactive shells for commands that do not need to
  mutate the parent shell.
- Gives remote agents a simpler command surface than shell aliases.

Cons:

- The installed scripts can drift from the checked-out analysis clone. A
  long-lived `DAYOA` environment may point at wrapper logic from an older repo
  version while the workset clone is on a newer ref.
- Multiple worksets on the same headnode become ambiguous unless every command
  requires an explicit initialized `DAY_ROOT`.
- `dy-a`, `dy-g`, and `dy-d` cannot fully behave like normal executable scripts
  because they need to mutate the current shell: conda environment, `DAY_ROOT`,
  `DAY_PROFILE`, `DAY_PROFILE_DIR`, `DAY_GENOME_BUILD`, `PATH`, Sentieon
  variables, and prompt state.
- Updating CLI wrapper behavior would require environment rebuild or repair
  instead of just changing the repository ref.
- Provenance is less clear: a run can be launched from one checkout while the
  installed command wrapper came from another version.

### Option: Add Repo-Local Shell Scripts To `PATH` During `source dyoainit`

Pros:

- Keeps command behavior version-coupled to the checked-out analysis clone.
- Avoids global command drift across worksets and repo refs.
- Lets `dy-r` and `dy-m` become real executables in `bin/`, avoiding alias
  expansion problems after initialization.
- Updating behavior remains a normal repository change.

Cons:

- Still requires `source dyoainit` before use so the shell has `DAY_ROOT`,
  project, budget, conda, completion, Sentieon, and profile context.
- If initialized from the wrong directory, `PATH` can still point to the wrong
  clone's `bin/`.
- Activation and deactivation remain shell-stateful operations.

### Recommended Direction

Keep activation as current-shell behavior, but replace the alias layer with
shell functions for stateful commands and repo-local executables for commands
that can safely run in a subprocess.

Target shape:

```bash
source dyoainit
dy-a slurm hg38_broad
dy-r produce_snv_concordances -p -j 20 -k
```

Implementation intent:

- `dy-a`, `dy-g`, and `dy-d`: shell functions installed by `source dyoainit`
  because they must mutate the current shell.
- `dy-r` and `dy-m`: executable repo-local scripts found through the
  initialized clone's `bin/` path.
- All runtime entrypoints should fail hard if required DayOA state is missing
  or points outside the active analysis clone.
- Avoid globally installed `DAYOA` wrappers unless they are thin dispatchers
  that refuse to run without an explicit, initialized `DAY_ROOT`.
