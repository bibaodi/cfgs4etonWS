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

# Inline math written with a bare pair of `$` (the notation most Markdown
# editors understand) is none of the three delimiters handled below, so a
# source that already used `$x$` was written back out verbatim and YNote
# rendered it as literal text instead of as math.
#
# Opener `(?<![\\$])\$(?![\s$])`:
#   - `(?<![\\$])` skips an escaped `\$` and the second `$` of a `$$` pair,
#   - `(?![\s$])` skips a `$$` pair from the front too, and refuses `$ 100`
#     (a space never opens inline math).
# Body `([^$\n]*?)`:
#   - may hold no `$` (so `$$` can never be swallowed as an empty body) and no
#     newline (inline math stays on one line); non-greedy, so consecutive
#     pairs on one line stay independent.
# Closer `(?<![\s\\])\$(?![\d$])`:
#   - `(?<![\s\\])` refuses `$ ` and `\$`,
#   - `(?![\d$])` refuses `$200`, which is what keeps prose like
#     `$100 ... $200` about prices from being rewritten as math.
_INLINE_DOLLAR_MATH = re.compile(
    r'(?<![\\$])\$(?![\s$])'
    r'([^$\n]*?)'
    r'(?<![\s\\])\$(?![\d$])'
)

# `\(` `\)` `\[` `\]` occurring *inside* an already-delimited `$...$` span are
# redundant: the outer `$` pair already marks the span as math. PDF-to-Markdown
# extraction nests the two notations anyway and emits e.g.
# `$\mathcal{\(\mathcal{F}\)}$`. Left alone, the `\(...\)` rule below would fire
# inside that span and splice a nested code span into the middle of the outer
# one (`$\mathcal{`$\mathcal{F}$`}$`); dropping the redundant pair keeps the
# formula valid instead: `$\mathcal{\mathcal{F}}$`.
_REDUNDANT_DELIMITERS = re.compile(r'\\[()\[\]]')

# A run of backticks plus everything up to the next run, i.e. a Markdown code
# span. Such text is literal by definition, so a `$...$` inside one must be
# left alone: it is either a quoted example (`` `$x$` ``) or already the YNote
# form this function produces, and re-wrapping it yields the doubly-delimited
# ` ``$x$`` `. The `$$` rule below already had to be line-anchored against
# exactly this hazard (see the `` `$$` 数学块 `` note there).
# Fenced ``` blocks are deliberately not covered here — see the caveat in
# `convert_dollar_inline_math`.
_CODE_SPAN = re.compile(r'`+[^`]*`+')


def _sub_outside_code_spans(pattern: 're.Pattern[str]', repl, text: str) -> str:
    """Apply `pattern.sub(repl, ...)` to everything but Markdown code spans."""
    out, cursor = [], 0
    for span in _CODE_SPAN.finditer(text):
        out.append(pattern.sub(repl, text[cursor:span.start()]))
        out.append(span.group(0))
        cursor = span.end()
    out.append(pattern.sub(repl, text[cursor:]))
    return ''.join(out)


def convert_dollar_inline_math(content: str) -> str:
    """
    Convert bare `$...$` inline math into YNote's inline form, i.e. `$...$`
    wrapped in a code span, dropping redundant nested delimiters on the way.

    Must run before the `\\(...\\)` / `\\[...\\]` rules of
    `convert_math_syntax`, so that a nested delimiter pair is removed by
    `_REDUNDANT_DELIMITERS` rather than expanded into a second code span.

    Inline code spans are skipped, but fenced ``` blocks are not: a `$...$`
    inside a fenced block is still rewritten. That is deliberate — it keeps
    this function line-oriented, matching the existing rules — and is only a
    problem for documents that quote math syntax inside a fence.
    """
    def to_ynote(match: re.Match) -> str:
        body = _REDUNDANT_DELIMITERS.sub('', match.group(1))
        return f'`${body}$`'

    return _sub_outside_code_spans(_INLINE_DOLLAR_MATH, to_ynote, content)


def convert_math_syntax(file_path: str) -> None:
    path = Path(file_path)

    if not path.is_file():
        print(f"Error: File '{file_path}' not found.")
        sys.exit(1)

    content = path.read_text(encoding='utf-8')

    # 0. Convert inline math written as a bare `$...$` pair. This runs first
    #    because it also strips the redundant `\(`/`\)` that PDF extraction
    #    nests inside such a span; see `convert_dollar_inline_math`.
    content = convert_dollar_inline_math(content)

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

    # Write to a sibling file rather than overwriting the source, so the
    # original stays available for a re-run or a diff:
    # e.g. `notes.md` -> `notes.mathformula.md`.
    output_path = path.with_suffix('.mathformula.md')
    output_path.write_text(content, encoding='utf-8')
    print(f"Successfully converted math syntax: '{path}' -> '{output_path}'.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        cmd = get_script_command()
        print(f"Usage: {cmd} <markdown_file>")
        sys.exit(1)

    convert_math_syntax(sys.argv[1])
