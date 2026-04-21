# README – Copy Top 5 Image+JSON Pairs
eton@260421 used for create app develop debug data set version.
files: 
    - scripts-py/copy_each_folder_top5ToHere-*
    - scripts-bash/copy_top5_pairs.sh 

README Contents:
----------
This application copies **only the first 5 image+JSON file pairs** from each immediate subfolder of a source directory into a destination directory, preserving the original subfolder structure.  
It is useful for sampling datasets, creating lightweight copies, or preparing subsets.

Two versions are provided:
- **Python** – cross‑platform, robust, handles special characters.
- **Bash** – lightweight, Unix‑only, good for simple use cases.

## Table of Contents
- [How It Works](#how-it-works)
- [Python Version](#python-version)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Usage](#usage-python)
  - [Example](#example-python)
- [Bash Version](#bash-version)
  - [Requirements](#requirements-1)
  - [Installation](#installation-1)
  - [Usage](#usage-bash)
  - [Example](#example-bash)
- [Notes](#notes)
- [License](#license)

---

## How It Works

Given:
- Source directory **A** with subfolders `s1`, `s2`, …  
  Each subfolder contains images (`.jpg`, `.jpeg`, `.png`, `.gif`, `.bmp`, `.tiff`) and matching `.json` files with the same base name.

The script will:
1. For each subfolder `s1`, scan all image files.
2. Keep only those that have a matching `.json` file (same name, different extension).
3. Sort the valid pairs by image filename (alphabetically).
4. Take the **first 5** pairs.
5. Copy **only those files** into the destination directory **B** inside the same relative subfolder (`B/s1/`, `B/s2/`, …).

No other files or folders are copied. If a subfolder has fewer than 5 pairs, all available pairs are copied.

---

## Python Version

### Requirements
- Python 3.6 or higher (no external libraries needed).

### Installation
1. Save the script as `copy_top5_pairs.py` anywhere.
2. Make it executable (optional):
   ```bash
   chmod +x copy_top5_pairs.py
   ```

### Usage (Python)
```bash
python copy_top5_pairs.py /path/to/source_A
```
- Run the command **from inside the destination folder B** (the folder where you want the copied subfolders and files to appear).
- The destination folder is always the **current working directory**.
- The source path can be absolute or relative.

**Optional:** If you want to run it without typing `python` every time, you can add a shebang and make it executable, then run:
```bash
./copy_top5_pairs.py /path/to/source_A
```

### Example (Python)

**Before** – source `A`:
```
A/
  cat/
    a.jpg   a.json
    b.jpg   b.json
    c.jpg   c.json
    d.jpg   d.json
    e.jpg   e.json
    f.jpg   f.json   (ignored – only top 5)
    extra.txt       (ignored)
  dog/
    x.png   x.json
    y.png   y.json   (only 2 pairs, both copied)
```

Run:
```bash
cd /path/to/destination_B
python /path/to/copy_top5_pairs.py /path/to/A
```

**After** – destination `B`:
```
B/
  cat/
    a.jpg   a.json
    b.jpg   b.json
    c.jpg   c.json
    d.jpg   d.json
    e.jpg   e.json
  dog/
    x.png   x.json
    y.png   y.json
```

---

## Bash Version

### Requirements
- Unix‑like environment (Linux, macOS, WSL).
- Standard utilities: `find`, `sort`, `head`, `basename`, `mkdir`, `cp`.
- No `jq` or other extra tools needed.

### Installation
1. Save the script as `copy_top5_pairs.sh`.
2. Make it executable:
   ```bash
   chmod +x copy_top5_pairs.sh
   ```

### Usage (Bash)
```bash
./copy_top5_pairs.sh /path/to/source_A
```
- Run **from inside the destination folder B**.
- The destination folder is the current working directory.

**Important:** The Bash version assumes that filenames contain **no spaces, newlines, or special characters** (like `*`, `?`, `[`). If your data may contain such characters, use the Python version instead.

### Example (Bash)

Same directory structure as above. Run:
```bash
cd /path/to/destination_B
/path/to/copy_top5_pairs.sh /path/to/A
```

The result in `B/` is identical to the Python example.

---

## Notes

- **Image extensions recognised** (both versions): `.jpg`, `.jpeg`, `.png`, `.gif`, `.bmp`, `.tiff` (case‑insensitive).
- **Matching rule:** For an image `name.jpg`, the script looks for `name.json` in the **same folder**. Files with different base names are ignored.
- **Sorting:** Pairs are sorted by image filename using **alphabetical order** (byte‑wise). Use leading zeros if you need numeric ordering (e.g., `01.jpg`, `02.jpg`).
- **Overwrite behaviour:** If a file already exists in the destination, it is **silently overwritten** (standard `cp` behaviour). To change this, modify the script.
- **Empty subfolders** or subfolders with no valid image‑JSON pairs are skipped with a message.
- **Performance:** The script only reads the top‑level subfolders (not recursive deeper than one level). Deeply nested structures are not processed.

## License

This application is free to use, modify, and distribute. No warranty is provided.
