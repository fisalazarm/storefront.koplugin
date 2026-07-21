# KOReader Lua Plugin Development: Google Antigravity Project Memory

**Target Models:** Gemini 3.1 Pro, Gemini 3.5 Flash, Claude Sonnet 4.6  
**Runtime Environment:** KOReader (Lua 5.1 / LuaJIT)  
**Test Framework:** Busted  
**Platform Architecture:** Google Antigravity (Editor, Terminal, and Browser surfaces)

---

## 1. Antigravity Agent & Multi-Model Orchestration Directives

This project utilizes Google Antigravity to orchestrate autonomous AI agents across the codebase. Agents must operate as proactive software engineers, adhering to strict e-ink hardware constraints and clean Object-Oriented principles.

* **Project Memory (`GEMINI.md`):** This file serves as the definitive system instruction and long-term memory for all autonomous agents operating within the project root.
* **Model Task Allocation:**
  * **Claude Sonnet 4.6:** Assign to complex multi-file planning, core architectural refactoring, and structured diff-editing where strict adherence to test suites is paramount.
  * **Gemini 3.1 Pro:** Assign to deep repository-wide reasoning, large-scale code exploration, and complex mathematical/business logic tasks leveraging its extensive context window.
  * **Gemini 3.5 Flash:** Assign to rapid iteration, boilerplate generation, localization string wrapping, and straightforward bug fixing.
* **Verifiable Artifact Generation:** Do not execute unverified code changes. Before modifying complex modules, agents must generate structured Antigravity Artifacts:
  * **Task Lists & Implementation Plans:** Outline the exact architecture and file breakdown before writing code.
  * **Walkthroughs & Code Diffs:** Provide clear summaries and precise unified diffs for user review upon completion.
* **Terminal & Test Autonomy:** Leverage terminal autonomy to run automated unit tests (`busted spec/`) independently. If a build or test fails, inspect terminal error logs and attempt self-correction autonomously before requesting human intervention.

---

## 2. Runtime Environment & E-Ink Hardware Constraints

KOReader operates on a specialized LuaJIT / Lua 5.1 runtime across resource-constrained e-ink readers (Kindle, Kobo, PocketBook, Android, Linux).

* **Strict Lua 5.1 / LuaJIT Compatibility:** Absolutely never use syntax or features introduced in Lua 5.2 or later (e.g., bitwise operators like `&`/`|`, `goto` statements, or `_ENV`). Rely on the standard `bit` library for bitwise manipulations.
* **E-Ink Display Optimization:** E-ink displays have low refresh frequencies and suffer from visual ghosting. Never design UI interactions involving continuous animations, high-frequency repaints, or polling loops. Group screen repaints into single, explicit refresh events.
* **Non-Blocking Execution:** Never block the primary UI thread with synchronous file I/O, heavy parsing, or network requests. Utilize asynchronous scheduling, coroutines, or background task chunks.
* **Memory Conservatism:** E-readers possess limited system RAM. Avoid allocating temporary tables inside high-frequency execution loops, and ensure all event listeners, timers, and UI widget references are explicitly garbage collected when plugins or dialogs close.

---

## 3. Code Architecture & KOReader OOP Patterns

KOReader uses a dedicated table-based Object-Oriented Programming model.

* **Standard Component Extension:** Always extend base KOReader component classes (`Widget`, `InputDialog`, base plugin modules) using the built-in `:extend{}` pattern. Never invent custom OOP metatable schemes.
* **Lifecycle Deferral:** Execute core setup during early startup hooks, but strictly defer UI widget instantiation and visual layout calculations until the reader view or file browser is actively ready.
* **Decoupled Layer Architecture:** Maintain strict separation between:
  1. **Data & Persistence Layer:** Settings serialization and configuration management.
  2. **Business Logic Layer:** Pure mathematical, parsing, and data manipulation algorithms (100% decoupled from UI elements).
  3. **Presentation Layer:** Graphical widgets, touch event routing, and screen repaints.
* **Event Dispatching:** Use KOReader's global event bus and dispatcher for inter-module communication rather than direct cross-table coupling.

---

## 4. Scope Control, Coding Standards & Error Handling

* **Zero Global Leakage:** Absolutely every variable, helper function, module table, and imported library must be explicitly declared within `local` scope.
* **Defensive Guard Clauses:** Validate all incoming parameters at the top of functions using early returns (guard clauses) to handle `nil`, undefined, or malformed data cleanly without deep indentation.
* **Standard Logging Exclusively:** Never use standard Lua `print()`. Import KOReader's `logger` module and use appropriate severity levels (`logger.dbg`, `logger.info`, `logger.warn`, `logger.err`), prefixing every message with the plugin identifier.
* **Protected Boundary Operations:** Wrap all external file system operations, JSON/data serialization, network requests, and OS-level calls in protected blocks (`pcall` or KOReader's safe wrappers) to guarantee that plugin exceptions never crash the primary application.

---

## 5. Documentation, Type Hinting & Localization

* **EmmyLua Annotations:** Every file, class definition, table schema, and function must include comprehensive EmmyLua docstring annotations (`---@class`, `---@field`, `---@param`, `---@return`) to enable static analysis and IDE intelligence.
* **Intent-Based Commenting:** Document *why* complex architectural workarounds or mathematical formulas exist; do not state *what* obvious syntax is doing. Mark future optimizations clearly using `TODO:` or `FIXME:`.
* **Universal Localization (`i18n`):** Every user-facing interface string (buttons, dialog labels, status messages, menu items) must be wrapped in gettext translation calls (`_("...")`). Never use string concatenation to build dynamic sentences; always employ formatted string templates with named or numbered placeholders.

---

## 6. Automated Testing Architecture (Busted Framework)

* **100% Logic Test Coverage:** Every public function, data parser, mathematical calculation, and state transition in the business logic layer must be accompanied by comprehensive unit tests written for the **Busted** framework (`spec/` directory).
* **Environment Mocking & Sandbox Isolation:**
  * Because unit tests execute in a desktop Lua environment without physical e-reader hardware, all business logic must be tested independently of graphical UI components.
  * Use a dedicated `spec_helper.lua` to mock KOReader global singletons (`G_reader`, `Device`, `UIManager`, loggers, and translation wrappers).
  * Sandbox all file I/O tests by mocking file system readers/writers or using ephemeral in-memory test directories.
* **Self-Verification Protocol:** Before finalizing any task, agents must autonomously run the Busted test suite via the terminal, verify zero regressions, check that no global variables leaked, and confirm that all user text is localized.
