"""CLI entry point for images-bin-matcher."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from images_bin_matcher.matcher import ImagesBinMatcher

logger = logging.getLogger(__name__)


def main() -> None:
    """Parse CLI arguments and run the images-bin-matcher workflow.

    Configures logging, validates input folders, then instantiates
    :class:`~images_bin_matcher.matcher.ImagesBinMatcher` and calls
    :meth:`~images_bin_matcher.matcher.ImagesBinMatcher.run`.

    Exits with status code 1 if either input folder does not exist.
    """
    parser = argparse.ArgumentParser(
        description="Match subfolder pairs across two input directories using SSIM."
    )
    parser.add_argument(
        "--folder-a",
        default="210822_ThyGlandSeg_hhN33In8Cases",
        help="Path to the first input folder (default: %(default)s)",
    )
    parser.add_argument(
        "--folder-b",
        default="220222_thyroidNodules-hh19",
        help="Path to the second input folder (default: %(default)s)",
    )
    parser.add_argument(
        "--output-dir",
        default="2labels-merged-dir",
        help="Output directory for matched_pairs.csv (default: %(default)s)",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.99,
        help="Minimum SSIM score for a match (default: %(default)s)",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity (default: %(default)s)",
    )

    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    folder_a = Path(args.folder_a).resolve()
    folder_b = Path(args.folder_b).resolve()
    output_dir = Path(args.output_dir)

    errors = []
    if not folder_a.exists():
        errors.append(folder_a)
    if not folder_b.exists():
        errors.append(folder_b)

    if errors:
        for missing in errors:
            logger.error("Input folder does not exist: %s", missing)
        sys.exit(1)

    logger.info(
        "Starting images-bin-matcher | folder_a=%s | folder_b=%s | output_dir=%s | threshold=%s",
        folder_a,
        folder_b,
        output_dir,
        args.threshold,
    )

    matcher = ImagesBinMatcher(
        folder_a=folder_a,
        folder_b=folder_b,
        output_dir=output_dir,
        threshold=args.threshold,
    )
    matcher.run()
