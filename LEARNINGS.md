# Learnings and Solution Guidelines

This document records rules, preferences, and key instructions from user sessions regarding how to design and propose solutions.

---

## 1. Simplicity First, Cleverness Second
- **Always Implement the Simplest Solution First**:
  - Default to straightforward, readable, and standard implementations.
  - Avoid premature optimization, over-engineering, complex state tracking, and custom data structures (such as manual circular buffers, pointer tracking, or modulo arithmetic) when standard language constructs (e.g. Swift arrays, standard algorithms) suffice.
- **Suggest Optimization Only When Absolutely Necessary**:
  - Only introduce or suggest complex, high-efficiency, or "clever" alternatives if profiling demonstrates a bottleneck, strict memory/CPU constraints demand it, or the user specifically requests optimization.
  - When suggesting optimizations, present them as follow-up options rather than jumping directly to them as the initial implementation.

---

## 2. Clarifying Requirements & Scope
- **Ask Before Guessing**:
  - If a request is ambiguous or underspecified (such as "simplify this" when no file is open), clarify the user's intent or provide clear options instead of making assumptions.
- **Strict Scope Limitation**:
  - Limit changes strictly to what was requested.
  - Do not refactor unrelated code, modify unrelated views, or touch working components outside the task scope.

---

## 3. API Compatibility & Quality
- **Preserve Existing Interfaces**:
  - Maintain public method signatures, property names, and behavior whenever refactoring or simplifying internal logic so that callers and unit tests do not break.
- **Verify with Unit Tests & Compiler Checks**:
  - Always verify changes against unit tests and Xcode diagnostics before concluding the task.

---

## 4. Continuous Learning & Evolution
- **Record New Learnings Along the Way**:
  - Continuously update this file whenever new preferences, architectural decisions, project conventions, or workflow feedback are established during interactions.
