---
name: read-symbol
description: Locate a named code symbol and read its implementation or a specific use when answering a source-level question in a local checkout.
---

# Read a symbol

1. Start with the location you already have. If the prompt or a Read Guard outline supplies a file and line range, read that range directly. Otherwise, use an available symbol index to go to the definition or find references. In a shell, use `rg -n -F -- 'symbol' path` in the narrowest relevant directory. If ripgrep is unavailable, use the checkout's search tool.
2. Choose the match that answers the question. A definition explains implementation, a caller shows use, and a test shows an expectation. For an ambiguous name, check its enclosing type or import before following it.
3. Read the declaration and the relevant body or call site with a range-capable reader. In a shell, use `sed -n 'START,ENDp' FILE` with numeric bounds around the match. Expand to the next branch, helper, or caller only when the first range leaves a specific question open.
4. Stop when the source supports the answer. Cite the file and line. Reserve a whole-file read such as `cat` for an explicit request or when the task genuinely needs the entire file.
