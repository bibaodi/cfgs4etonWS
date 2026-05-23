"""Smoke tests for images_bin_matcher.matcher."""

from __future__ import annotations

import csv
import tempfile
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from images_bin_matcher.matcher import PROBE_IMAGES, ImagesBinMatcher


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_frms_subfolder(parent: Path, name: str, size: tuple[int, int] = (64, 64)) -> Path:
    """Create a *_frms subfolder with all three probe images."""
    sub = parent / name
    sub.mkdir(parents=True, exist_ok=True)
    arr = np.random.randint(0, 256, (*size, 3), dtype=np.uint8)
    for probe in PROBE_IMAGES:
        Image.fromarray(arr).save(sub / probe)
    return sub


# ---------------------------------------------------------------------------
# Smoke tests — import and instantiation
# ---------------------------------------------------------------------------

def test_import():
    """Module and class can be imported without error."""
    from images_bin_matcher.matcher import ImagesBinMatcher  # noqa: F401


def test_instantiation(tmp_path):
    """ImagesBinMatcher can be instantiated with valid paths."""
    folder_a = tmp_path / "a"
    folder_b = tmp_path / "b"
    output_dir = tmp_path / "out"
    folder_a.mkdir()
    folder_b.mkdir()

    matcher = ImagesBinMatcher(folder_a, folder_b, output_dir)
    assert matcher.folder_a == folder_a
    assert matcher.folder_b == folder_b
    assert matcher.output_dir == output_dir
    assert matcher.threshold == 0.99


def test_instantiation_custom_threshold(tmp_path):
    """Custom threshold is stored correctly."""
    matcher = ImagesBinMatcher(tmp_path, tmp_path, tmp_path, threshold=0.95)
    assert matcher.threshold == 0.95


# ---------------------------------------------------------------------------
# _discover_subfolders
# ---------------------------------------------------------------------------

def test_discover_subfolders_finds_valid(tmp_path):
    """Valid *_frms subfolders with all probe images are discovered."""
    _make_frms_subfolder(tmp_path, "case1_frms")
    _make_frms_subfolder(tmp_path, "case2_frms")

    matcher = ImagesBinMatcher(tmp_path, tmp_path, tmp_path)
    found = matcher._discover_subfolders(tmp_path)
    names = [p.name for p in found]
    assert "case1_frms" in names
    assert "case2_frms" in names


def test_discover_subfolders_skips_non_frms(tmp_path):
    """Directories not ending in _frms are ignored."""
    (tmp_path / "other_dir").mkdir()
    _make_frms_subfolder(tmp_path, "valid_frms")

    matcher = ImagesBinMatcher(tmp_path, tmp_path, tmp_path)
    found = matcher._discover_subfolders(tmp_path)
    names = [p.name for p in found]
    assert "other_dir" not in names
    assert "valid_frms" in names


def test_discover_subfolders_skips_missing_probe(tmp_path):
    """Subfolders missing a probe image are skipped."""
    incomplete = tmp_path / "incomplete_frms"
    incomplete.mkdir()
    # Only write two of the three probe images
    for probe in PROBE_IMAGES[:2]:
        Image.fromarray(np.zeros((4, 4, 3), dtype=np.uint8)).save(incomplete / probe)

    matcher = ImagesBinMatcher(tmp_path, tmp_path, tmp_path)
    found = matcher._discover_subfolders(tmp_path)
    assert not any(p.name == "incomplete_frms" for p in found)


# ---------------------------------------------------------------------------
# _load_grayscale
# ---------------------------------------------------------------------------

def test_load_grayscale_returns_2d_array(tmp_path):
    """_load_grayscale returns a 2-D uint8 array."""
    img_path = tmp_path / "test.png"
    Image.fromarray(np.zeros((8, 8, 3), dtype=np.uint8)).save(img_path)

    matcher = ImagesBinMatcher(tmp_path, tmp_path, tmp_path)
    arr = matcher._load_grayscale(img_path)
    assert arr.ndim == 2
    assert arr.dtype == np.uint8


# ---------------------------------------------------------------------------
# _compare_pair
# ---------------------------------------------------------------------------

def test_compare_pair_identical_images(tmp_path):
    """Comparing a subfolder with itself returns scores of 1.0."""
    sub = _make_frms_subfolder(tmp_path, "same_frms")

    matcher = ImagesBinMatcher(tmp_path, tmp_path, tmp_path)
    scores = matcher._compare_pair(sub, sub)
    assert scores is not None
    assert all(s == pytest.approx(1.0) for s in scores)


def test_compare_pair_returns_none_on_missing_probe(tmp_path):
    """Returns None when a probe image is missing from one subfolder."""
    sub_a = _make_frms_subfolder(tmp_path / "a", "case_frms")
    sub_b = tmp_path / "b" / "case_frms"
    sub_b.mkdir(parents=True)
    # sub_b has no probe images

    matcher = ImagesBinMatcher(tmp_path / "a", tmp_path / "b", tmp_path)
    result = matcher._compare_pair(sub_a, sub_b)
    assert result is None


# ---------------------------------------------------------------------------
# _write_csv
# ---------------------------------------------------------------------------

def test_write_csv_creates_output_dir(tmp_path):
    """_write_csv creates output_dir if it does not exist."""
    output_dir = tmp_path / "new_output"
    matcher = ImagesBinMatcher(tmp_path, tmp_path, output_dir)
    matcher._write_csv([])
    assert output_dir.exists()


def test_write_csv_header_and_rows(tmp_path):
    """CSV has correct header and one row per match."""
    output_dir = tmp_path / "out"
    matcher = ImagesBinMatcher(tmp_path, tmp_path, output_dir)
    matches = [
        {
            "subfolder_a": "a_frms",
            "subfolder_b": "b_frms",
            "score_frm1": 0.9999991,
            "score_frm2": 0.9999992,
            "score_frm3": 0.9999993,
        }
    ]
    matcher._write_csv(matches)

    csv_path = output_dir / "matched_pairs.csv"
    assert csv_path.exists()

    with csv_path.open() as fh:
        reader = csv.DictReader(fh)
        rows = list(reader)

    assert len(rows) == 1
    assert rows[0]["subfolder_a"] == "a_frms"
    assert rows[0]["subfolder_b"] == "b_frms"
    # Scores rounded to 6 dp
    assert float(rows[0]["score_frm1"]) == pytest.approx(0.999999, abs=1e-6)


# ---------------------------------------------------------------------------
# run() — end-to-end smoke
# ---------------------------------------------------------------------------

def test_run_produces_csv(tmp_path):
    """run() writes matched_pairs.csv and returns a list."""
    folder_a = tmp_path / "a"
    folder_b = tmp_path / "b"
    output_dir = tmp_path / "out"

    # Create identical subfolders in both — should match
    _make_frms_subfolder(folder_a, "case_frms", size=(16, 16))
    # Copy the same images to folder_b to guarantee a match
    sub_b = folder_b / "case_frms"
    sub_b.mkdir(parents=True)
    for probe in PROBE_IMAGES:
        src = folder_a / "case_frms" / probe
        Image.open(src).save(sub_b / probe)

    matcher = ImagesBinMatcher(folder_a, folder_b, output_dir, threshold=0.99)
    results = matcher.run()

    assert isinstance(results, list)
    assert (output_dir / "matched_pairs.csv").exists()
    assert len(results) == 1
    assert results[0]["subfolder_a"] == "case_frms"
    assert results[0]["subfolder_b"] == "case_frms"
