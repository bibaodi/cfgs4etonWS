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

    path.write_text(content, encoding='utf-8')
    print(f"Successfully converted math syntax in '{file_path}'.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        cmd = get_script_command()
        print(f"Usage: {cmd} <markdown_file>")
        sys.exit(1)

    convert_math_syntax(sys.argv[1])
