#!/usr/bin/env python3
import sys
import re
from pathlib import Path

def get_script_command() -> str:
    """
    Returns a clean command prefix for usage messages, accurately reflecting
    whether the script was run as `python3 script.py`, `./script.py`, or `python app.py`.
    """
    script_path = Path(sys.argv[0])
    
    # Python 3.10+ provides the raw command-line arguments passed to the executable
    if hasattr(sys, 'orig_argv') and len(sys.orig_argv) > 1:
        # If the interpreter was called explicitly (e.g. "python3 app.py" or "python -m ...")
        interpreter = Path(sys.orig_argv[0]).name
        if interpreter.startswith("python"):
            return f"{interpreter} {script_path.name}"
            
    # Fallback for direct execution via shebang (e.g. ./convert_math.py) or older Python
    return script_path.name if script_path.is_file() else f"python3 {script_path.name}"

def convert_math_syntax(file_path: str) -> None:
    path = Path(file_path)
    
    if not path.is_file():
        print(f"Error: File '{file_path}' not found.")
        sys.exit(1)

    content = path.read_text(encoding='utf-8')

    # 1. Convert block math: \[...\] -> ```math\n...\n```
    content = re.sub(
        r'\\\[\s*\n?(.*?)\n?\s*\\\]',
        r'```math\n\1\n```',
        content,
        flags=re.DOTALL
    )

    # 2. Convert inline math: \(...\) -> `$ ... $`
    content = re.sub(
        r'\\\((.*?)\\\)',
        r'`$\1$`',
        content
    )

    # 3. Convert display math: $$...$$ -> ```math\n...\n```
    #    - Match only `$$` that stands ALONE on its own line:
    #      `^\$\$[ \t]*$`. The line anchors (activated by re.MULTILINE) are
    #      what prevent the regex from mis-pairing an inline `$$` inside a
    #      code span — such as the phrase `` `$$` 数学块 `` in the intro —
    #      with the next real display-math delimiter further down the file.
    #      Without the anchors, the first (inline) `$$` pairs with the first
    #      real delimiter, and every subsequent delimiter pair is shifted by
    #      one, which is what produced the corrupted “``` before, ```math
    #      after” swap in 3.md.
    #    - re.MULTILINE makes `^` / `$` match at line boundaries; re.DOTALL
    #      lets the captured body span newlines.
    #    - `[ \t]*` (not `\s*`) keeps the match from swallowing the newline
    #      itself, so the surrounding blank lines are preserved.
    #    - Non-greedy `.*?` stops at the first closing `$$` line, so
    #      consecutive blocks stay independent.
    content = re.sub(
        r'(?m)^\$\$[ \t]*$\n(.*?)\n^\$\$[ \t]*$',
        lambda m: '```math\n' + m.group(1).rstrip() + '\n```',
        content,
        flags=re.DOTALL,
    )

    path.write_text(content, encoding='utf-8')
    print(f"Successfully converted math syntax in '{file_path}'.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        cmd = get_script_command()
        print(f"Usage: {cmd} <markdown_file>")
        sys.exit(1)

    convert_math_syntax(sys.argv[1])
