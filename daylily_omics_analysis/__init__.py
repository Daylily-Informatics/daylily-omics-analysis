from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

from .workflow_catalog import WorkflowCatalogError, load_workflow_catalog, render_workflow_command

try:
    __version__ = version("daylily-omics-analysis")
except PackageNotFoundError:  # pragma: no cover - local source tree before installation
    __version__ = "0.0.0"

__all__ = [
    "__version__",
    "WorkflowCatalogError",
    "load_workflow_catalog",
    "render_workflow_command",
]
