#!/usr/bin/env python3
"""Fetch concordance results from headnode via SSH."""
import subprocess
import sys

TESTS = [
    "test-hybrid-cli-ilmn-ont-3x",
    "test-hybrid-cli-ilmn-pb-3x",
    "test-hybrid-cli-ug-ont-3x",
    "test-hybrid-cli-ug-pb-3x",
    "test-hybrid-mod-ilmn-ont-3x",
    "test-hybrid-mod-ilmn-pb-3x",
    "test-hybrid-mod-ug-ont-3x",
    "test-hybrid-mod-ug-pb-3x",
    "test-hybrid-mod-roche-ont-3x",
    "test-hybrid-mod-roche-pb-3x",
]

SSH_CMD = ["ssh", "-i", "~/.ssh/lsmc-omics-us-west-2.pem", "-o", "ConnectTimeout=30", "ubuntu@44.231.76.175"]

def get_concordance(test_name):
    """Get SNPts and INDELts F1 for a test."""
    for build in ["hg38", "hg38_broad"]:
        path = f"/fsx/analysis_results/ubuntu/{test_name}/daylily-omics-analysis/results/day/{build}/other_reports/giab_concordance_mqc.tsv"
        cmd = SSH_CMD + [f"cat {path} 2>/dev/null"]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode == 0 and result.stdout.strip():
                lines = result.stdout.strip().split("\n")
                snp_f1 = indel_f1 = "N/A"
                for line in lines:
                    parts = line.split("\t")
                    if len(parts) >= 9:
                        if "SNPts" in parts[0]:
                            snp_f1 = parts[8]
                        elif "INDELts" in parts[0]:
                            indel_f1 = parts[8]
                if snp_f1 != "N/A" or indel_f1 != "N/A":
                    return snp_f1, indel_f1, build
        except Exception as e:
            pass
    return "N/A", "N/A", None

def main():
    print("=== HYBRID TEST CONCORDANCE REPORT ===\n")
    print(f"{'Test':<35} {'Build':<12} {'SNPts F1':<12} {'INDELts F1':<12}")
    print("-" * 75)
    
    for test in TESTS:
        snp, indel, build = get_concordance(test)
        build_str = build if build else "N/A"
        print(f"{test:<35} {build_str:<12} {snp:<12} {indel:<12}")
    
    print("\n=== END REPORT ===")

if __name__ == "__main__":
    main()

