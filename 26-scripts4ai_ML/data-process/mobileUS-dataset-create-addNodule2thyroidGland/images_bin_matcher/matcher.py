"""Core matcher module for images-bin-matcher."""

from __future__ import annotations

import csv
import logging
from pathlib import Path

import numpy as np
from PIL import Image
from skimage.metrics import structural_similarity as ssim

logger = logging.getLogger(__name__)

PROBE_IMAGES: tuple[str, ...] = ("frm-0001.png", "frm-0002.png", "frm-0003.png")


class ImagesBinMatcher:
    """Identifies matching subfolder pairs across two input directories.

    Compares the structural similarity (SSIM) of the first three frame images
    in each ``*_frms`` subfolder.  A pair is considered a match when all three
    SSIM scores exceed the configured threshold.

    Args:
        folder_a: Path to the first input folder.
        folder_b: Path to the second input folder.
        output_dir: Directory where ``matched_pairs.csv`` will be written.
        threshold: Minimum SSIM score required for all three probe images to
            consider a subfolder pair a match.  Defaults to ``0.99``.
    """

    def __init__(
        self,
        folder_a: Path,
        folder_b: Path,
        output_dir: Path,
        threshold: float = 0.99,
    ) -> None:
        self.folder_a = folder_a
        self.folder_b = folder_b
        self.output_dir = output_dir
        self.threshold = threshold

    def _discover_subfolders(self, folder: Path) -> list[Path]:
        """Return sorted list of direct ``*_frms`` subdirectories in *folder*.

        Each candidate subdirectory is validated to contain all three probe
        images (``frm-0001.png``, ``frm-0002.png``, ``frm-0003.png``).
        Subdirectories that are missing any probe image are skipped with a
        WARNING log message.  An INFO message is emitted with the total count
        of valid subfolders found.

        Args:
            folder: The parent directory to search for ``*_frms`` children.

        Returns:
            Sorted list of :class:`~pathlib.Path` objects for valid ``*_frms``
            subdirectories that contain all three probe images.
        """
        candidates = sorted(
            p for p in folder.iterdir() if p.is_dir() and p.name.endswith("_frms")
        )

        valid: list[Path] = []
        for sub in candidates:
            missing = [img for img in PROBE_IMAGES if not (sub / img).is_file()]
            if missing:
                logger.warning(
                    "Skipping subfolder %s — missing probe image(s): %s",
                    sub,
                    ", ".join(missing),
                )
            else:
                valid.append(sub)

        logger.info(
            "Discovered %d valid subfolder(s) in %s", len(valid), folder
        )
        return valid

    def _load_grayscale(self, path: Path) -> np.ndarray:
        """Open a PNG image and return it as a grayscale NumPy array.

        Args:
            path: Filesystem path to the PNG file.

        Returns:
            2-D ``numpy.ndarray`` of dtype ``uint8`` representing the
            grayscale pixel values.

        Raises:
            OSError: If the file cannot be opened or read.
        """
        img = Image.open(path).convert("L")
        return np.array(img)

    def _compare_pair(
        self, sub_a: Path, sub_b: Path
    ) -> tuple[float, float, float] | None:
        """Compute SSIM scores for the three probe images between two subfolders.

        Loads ``frm-0001.png``, ``frm-0002.png``, and ``frm-0003.png`` from
        each subfolder as grayscale arrays.  When the two images for a given
        probe differ in pixel dimensions, the smaller image is resized to the
        larger image's dimensions using ``PIL.Image.LANCZOS`` resampling before
        the SSIM is computed.

        Args:
            sub_a: Path to a subfolder from ``folder_a``.
            sub_b: Path to a subfolder from ``folder_b``.

        Returns:
            A 3-tuple ``(score_frm1, score_frm2, score_frm3)`` of SSIM values
            in ``[0.0, 1.0]``, or ``None`` if any probe image is missing or
            unreadable.

        Raises:
            OSError: Re-raised for unrecoverable image read errors after
                logging at ERROR level.
        """
        scores: list[float] = []

        for probe in PROBE_IMAGES:
            path_a = sub_a / probe
            path_b = sub_b / probe

            if not path_a.is_file() or not path_b.is_file():
                logger.warning(
                    "Probe image missing — skipping pair (%s, %s): %s",
                    sub_a.name,
                    sub_b.name,
                    probe,
                )
                return None

            try:
                arr_a = self._load_grayscale(path_a)
                arr_b = self._load_grayscale(path_b)
            except OSError as exc:
                logger.error(
                    "Unreadable image file for pair (%s, %s) probe %s: %s",
                    sub_a.name,
                    sub_b.name,
                    probe,
                    exc,
                )
                raise

            # Resize smaller image to larger dimensions if they differ
            if arr_a.shape != arr_b.shape:
                h_a, w_a = arr_a.shape
                h_b, w_b = arr_b.shape
                target_w = max(w_a, w_b)
                target_h = max(h_a, h_b)
                logger.debug(
                    "Resizing probe %s for pair (%s, %s): (%d×%d) vs (%d×%d) → (%d×%d)",
                    probe,
                    sub_a.name,
                    sub_b.name,
                    w_a, h_a, w_b, h_b,
                    target_w, target_h,
                )
                if (h_a, w_a) < (h_b, w_b):
                    img_a = Image.fromarray(arr_a).resize(
                        (target_w, target_h), Image.LANCZOS
                    )
                    arr_a = np.array(img_a)
                else:
                    img_b = Image.fromarray(arr_b).resize(
                        (target_w, target_h), Image.LANCZOS
                    )
                    arr_b = np.array(img_b)

            score = float(ssim(arr_a, arr_b, data_range=arr_a.max() - arr_a.min()))
            logger.debug(
                "SSIM %s | (%s, %s) = %.6f",
                probe,
                sub_a.name,
                sub_b.name,
                score,
            )
            scores.append(score)

        return (scores[0], scores[1], scores[2])

    def _write_csv(self, matches: list[dict]) -> None:
        """Write matched pairs to ``matched_pairs.csv`` inside ``output_dir``.

        Creates ``output_dir`` if it does not already exist.  Each row records
        the subfolder names and the three SSIM scores rounded to 6 decimal
        places.  Logs an INFO message with the CSV path and total match count
        upon completion.

        Args:
            matches: List of match dictionaries, each containing keys
                ``subfolder_a``, ``subfolder_b``, ``score_frm1``,
                ``score_frm2``, and ``score_frm3``.
        """
        self.output_dir.mkdir(parents=True, exist_ok=True)
        csv_path = self.output_dir / "matched_pairs.csv"

        with csv_path.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(
                ["subfolder_a", "subfolder_b", "score_frm1", "score_frm2", "score_frm3"]
            )
            for match in matches:
                writer.writerow([
                    match["subfolder_a"],
                    match["subfolder_b"],
                    round(match["score_frm1"], 6),
                    round(match["score_frm2"], 6),
                    round(match["score_frm3"], 6),
                ])

        logger.info(
            "CSV written to %s — %d match(es) recorded.", csv_path, len(matches)
        )

    def run(self) -> list[dict]:
        """Execute the full matching workflow and return the list of matches.

        Discovers all valid ``*_frms`` subfolders in both input folders, then
        evaluates every (sub_a, sub_b) pair by computing SSIM scores via
        :meth:`_compare_pair`.  Pairs where all three scores exceed
        :attr:`threshold` are collected as matches.  Progress is logged at
        INFO level every 10 pairs evaluated.  Results are written to CSV via
        :meth:`_write_csv` before being returned.

        Returns:
            List of match dictionaries, each containing keys
            ``subfolder_a``, ``subfolder_b``, ``score_frm1``,
            ``score_frm2``, and ``score_frm3``.
        """
        subs_a = self._discover_subfolders(self.folder_a)
        subs_b = self._discover_subfolders(self.folder_b)

        matches: list[dict] = []
        pairs_evaluated = 0

        a_matched_b = False
        for sub_a in subs_a:
            if a_matched_b:
                a_matched_b = False

            for sub_b in subs_b:
                scores = self._compare_pair(sub_a, sub_b)
                pairs_evaluated += 1

                if pairs_evaluated % 10 == 0:
                    logger.info("Pairs evaluated so far: %d", pairs_evaluated)

                if scores is not None and all(s > self.threshold for s in scores):
                    matches.append({
                        "subfolder_a": sub_a.name,
                        "subfolder_b": sub_b.name,
                        "score_frm1": round(scores[0], 6),
                        "score_frm2": round(scores[1], 6),
                        "score_frm3": round(scores[2], 6),
                    })
                    a_matched_b = True
                    break #skip all next b;

        self._write_csv(matches)
        return matches
