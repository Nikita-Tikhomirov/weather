from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import unittest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Run unittest discovery and exit with the test result code.'
    )
    parser.add_argument(
        '--start',
        default='tests',
        help='Directory where unittest discovery starts.',
    )
    parser.add_argument(
        '--pattern',
        default='test*.py',
        help='File pattern used by unittest discovery.',
    )
    parser.add_argument(
        '--verbosity',
        default=2,
        type=int,
        help='unittest output verbosity.',
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(repo_root))
    try:
        suite = unittest.defaultTestLoader.discover(
            start_dir=args.start,
            pattern=args.pattern,
        )
        result = unittest.TextTestRunner(verbosity=args.verbosity).run(suite)
        code = 0 if result.wasSuccessful() else 1
    except Exception as exc:
        print(f'unittest discovery failed: {exc}', file=sys.stderr)
        code = 1
    finally:
        sys.stdout.flush()
        sys.stderr.flush()

    # CI can keep running when tests leave non-daemon helper threads around.
    # The test result has already been reported, so terminate deterministically.
    os._exit(code)


if __name__ == '__main__':
    main()
