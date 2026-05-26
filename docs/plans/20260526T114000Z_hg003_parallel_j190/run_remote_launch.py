from pathlib import Path

from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell


SCRIPT_PATH = Path(__file__).with_name("remote_launch_ds004_ds005_j190.sh")


def main() -> None:
    script = SCRIPT_PATH.read_text(encoding="utf-8")
    try:
        result = run_shell(
            "i-03f1a49bbc4e39d4b",
            "us-west-2",
            script,
            profile="lsmc",
            timeout=240,
            poll_interval=3,
            comment="Launch HG003 DS-004 and DS-005 with -j 190",
        )
        print(result.stdout)
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
    except SsmCommandFailedError as exc:
        result = exc.args[1]
        print(result.stdout)
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
        raise


if __name__ == "__main__":
    main()
