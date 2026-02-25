# PyInterp — A Python Interpreter in Objective-C

A fully tree-walking Python interpreter written in Objective-C, supporting
a rich subset of Python 3: functions, classes, closures, recursion, built-ins,
list/dict/string methods, for/while loops, and more.

---

## Requirements

| Tool      | Notes                                 |
|-----------|---------------------------------------|
| macOS     | 10.13+ (uses Foundation + ARC)        |
| Xcode CLT | `xcode-select --install`              |
| Python 3  | For the benchmark comparison          |

---

## Quick Start

```bash
# 1. Unzip
unzip pyinterp.zip
cd pyinterp

# 2. Build  (single command!)
make

# 3. Run a script
./pyinterp tests/hello.py
./pyinterp tests/fibonacci.py
./pyinterp tests/oop.py
./pyinterp tests/benchmark.py

# 4. Run built-in test suite
make test

# 5. Benchmark: ObjC interpreter vs. CPython
bash bench.sh
```

---

## What the benchmark does

`bench.sh` runs `tests/benchmark.py` three times each through:
- **The ObjC interpreter** (`./pyinterp`)
- **Your system Python 3** (`python3`)

It prints per-run times, best, average, and a ratio comparison — all nicely
coloured in your terminal.

---

## Supported Python Features

- **Types**: int, float, str, bool, None, list, dict, tuple
- **Control flow**: if / elif / else, while, for … in, break, continue
- **Functions**: def, return, default args, keyword args, closures, recursion
- **Classes**: class, `__init__`, instance attributes and methods, `self`
- **Operators**: arithmetic (+−×÷//%), power (**), comparisons, and/or/not
- **Built-ins**: print, len, range, int, float, str, bool, abs, max, min,
  sum, type, isinstance, input, sorted, enumerate, zip, list, dict
- **String methods**: upper, lower, strip, split, join, replace, find,
  startswith, endswith, count, format
- **List methods**: append, pop, extend, insert, remove, sort, reverse,
  index, count
- **Dict methods**: keys, values, items, get, update, pop
- **Math module**: sqrt, pow, floor, ceil, pi, e

---

## Project Layout

```
pyinterp/
├── Makefile          ← build everything with `make`
├── bench.sh          ← timing comparison script
├── main.m            ← entry point
├── include/
│   ├── Lexer.h
│   ├── ASTNode.h
│   ├── Parser.h
│   └── Interpreter.h
├── src/
│   ├── Lexer.m       ← tokeniser
│   ├── ASTNode.m     ← AST node
│   ├── Parser.m      ← recursive-descent parser
│   └── Interpreter.m ← tree-walking evaluator + builtins
└── tests/
    ├── hello.py
    ├── fibonacci.py
    ├── oop.py
    └── benchmark.py  ← used by bench.sh
```
