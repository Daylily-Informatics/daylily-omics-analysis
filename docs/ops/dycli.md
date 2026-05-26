# DayOA CLI Notes

DayOA CLI work starts in the `DAY-EC` conda environment:

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
```

Initialize a workset clone, activate a profile, then run targets:

```bash
source dyoainit
dy-a local hg38
dy-r help
dy-r produce_multiqc_all -n -p -j 1
```

Useful commands:

- `dy-r --version` prints the DayOA command wrapper version.
- `day-monitor` inspects workflow state from an active analysis directory.
- `dy-r <target> -n -p -j 1` performs a dry-run with printed commands.

On a headnode, connect only through `daylily-ec`/SSM and use a login bash shell before invoking `source dyoainit`, `dy-a`, `dy-r`, or `day-monitor`.

