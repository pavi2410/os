# Phase 8 — Process environment

**Goal:** Make processes, the serial console, environment, and basic IPC behave like a Unix-like OS — before virtual memory expansion and new filesystems.

**Depends on:** [Phase 7 — Copy-on-write fork](07-copy-on-write-fork.md) (cheap fork helps pipes and job control)

**Unlocks:** [Phase 9 — Virtual memory and page cache](09-virtual-memory-and-page-cache.md), [Phase 14 — GUI](14-gui.md) (input/event path)

---

## Rationale

Interaction today is entirely over **serial**: shell, `curl` output, kernel panics. Several correctness gaps block “normal” Unix behavior:

- `cd`/`pwd` are **shell-local** — children don't inherit kernel cwd ([`userspace/shell/cwd.zig`](../../userspace/shell/cwd.zig))
- No **environment variables** — kernel `execve` ignores `envp` ([`kernel/syscall/handlers.zig`](../../kernel/syscall/handlers.zig)); loader pushes an empty environ ([`kernel/mm/user_loader.zig`](../../kernel/mm/user_loader.zig))
- No **`PATH`** — shell hardcodes `/BIN/<NAME>` ([`userspace/shell/cmd/run.zig`](../../userspace/shell/cmd/run.zig))
- No **pipes** or FD duplication — no `cmd | cmd`, redirects, or `2>&1`
- **Init is the shell** ([`kernel/proc/init_shell.zig`](../../kernel/proc/init_shell.zig)) — no PID 1 reap loop or service spawning
- No **`/dev`** nodes — programs can't open `/dev/null` or a named TTY

Polish this layer before `mmap`, ext2, and SMP.

---

## Checklist

### TTY / console

- [ ] Document serial as primary console (`/dev/ttyS0` or equivalent)
- [ ] Review [`drivers/tty.zig`](../../kernel/drivers/tty.zig) — echo, erase, canonical mode edge cases
- [ ] ANSI: verify common sequences used by tools (`curl`, future pagers)
- [ ] TTY ioctls or minimal equivalents (`tcsetattr` subset)
- [ ] Clearer stderr vs stdout semantics

### devfs (minimal)

- [ ] Pseudo filesystem or static device nodes under `/dev`
- [ ] `/dev/null`, `/dev/zero`
- [ ] `/dev/ttyS0` (or console device) openable from user programs
- [ ] Mount or populate `/dev` at boot (init or kernel thread)

### Kernel working directory

- [ ] Per-process cwd in [`proc/process.zig`](../../kernel/proc/process.zig)
- [ ] Syscalls: `chdir`, `getcwd`
- [ ] Wire cwd into VFS path resolution (`open`, `stat`, `unlink`, `mkdir`, …)
- [ ] Migrate shell `cd`/`pwd` to syscalls (remove shell-only cwd or keep as thin wrapper)
- [ ] Integration: shell `cd` → fork/exec child opens relative path correctly

### Environment variables and PATH

Today the shell passes `exec_envp = { null }` and the kernel discards the third `execve` argument. Programs cannot read `getenv("…")` and command lookup does not search `PATH`.

#### Kernel / loader

- [ ] Parse `envp` in `sysExecve` ([`handlers.zig`](../../kernel/syscall/handlers.zig)) — stop ignoring the third argument
- [ ] Store environ per process in [`proc/process.zig`](../../kernel/proc/process.zig) (pointer list or contiguous strings in user memory)
- [ ] Extend [`pushArgv`](../../kernel/mm/user_loader.zig) (or sibling helper) to place **envp strings + pointers** on the user stack per SysV ABI
- [ ] `fork` copies parent environ to child (same rules as Linux: shared until written — COW from [phase 7](07-copy-on-write-fork.md) applies once pages are mapped)
- [ ] `execve` replaces environ entirely with the new `envp`
- [ ] Document max env count / total env bytes (bounded, like argv limits today)

#### Shell

- [ ] In-process environ table (e.g. `KEY=value` strings, `export` builtin)
- [ ] Default at startup: at least `PATH=/BIN`, `PWD=/` (or sync `PWD` with cwd)
- [ ] Optional defaults: `HOME=/`, `SHELL=/BIN/SHELL` — document chosen values
- [ ] `export NAME=value` and `export NAME` (inherit from shell table)
- [ ] Pass full environ to `execve` (replace empty [`exec_envp`](../../userspace/shell/cmd/run.zig))
- [ ] **`PATH` lookup** — for bare command names, search colon-separated directories in order
- [ ] Still support explicit paths (`/BIN/curl`, `./tool` once cwd is kernel-side)
- [ ] Uppercase FAT 8.3 names: document whether `PATH` entries are normalized or `/BIN` stays canonical

#### Userspace ulib (minimal)

- [ ] `getenv(name)` — scan process environ on stack or via future syscall stub
- [ ] Optional: `setenv` / `putenv` for shell and tests (can be shell-only at first)

#### Tests

- [ ] Integration: `export FOO=bar`, run stub or shell builtin child that prints `FOO`
- [ ] Integration: `PATH=/BIN` (or multi-dir once second dir exists) — bare `curl` resolves without hardcoded prefix in `run.zig`
- [ ] Host or integration: `execve` with non-empty `envp` — child stack contains expected strings

### IPC and file descriptors

- [ ] `pipe` / `pipe2` — ring buffer between two FDs
- [ ] `dup`, `dup2`, `fcntl(F_DUPFD, …)` — FD table manipulation
- [ ] Shell pipelines: `ls | wc` (even if `wc` is a stub)
- [ ] Shell redirects: `>`, `>>`, `2>&1` (stretch: heredocs)
- [ ] `fork` inherits pipe FDs correctly; `execve` preserves them

### Signals (minimal Linux subset)

- [ ] Signal numbers and `sigaction` table per process (or minimal handler dispatch)
- [ ] Deliver `SIGCHLD` to parent on child exit (shell `wait` UX)
- [ ] Deliver `SIGINT` on serial break or `^C` equivalent
- [ ] Syscalls: `rt_sigaction`, `rt_sigprocmask`, `kill` (smallest viable subset)
- [ ] Default dispositions: terminate, ignore, stop — document deviations from Linux

### Init / PID 1

- [ ] Separate **init process** from interactive shell (e.g. `/BIN/init` or kernel-launched stub)
- [ ] PID 1 `wait` loop — reap orphaned children
- [ ] Init spawns shell (or getty) as a child, not as init itself
- [ ] Document boot chain: kernel → init → shell

### Shell integration

- [ ] Shell ignores `SIGINT` while running builtins; child receives `SIGINT`
- [ ] Optional: background jobs (`cmd &`, `fg`, `bg`) — stretch goal

### Process groups / sessions (stretch)

- [ ] `setpgid`, `setsid` — only if job control is pursued
- [ ] Controlling terminal concept for serial

### Tests

- [ ] Integration: `^C` during `curl` or `ping`; shell returns to prompt
- [ ] Integration: child exit wakes blocked parent (`wait4`)
- [ ] Integration: `echo foo | cat` or equivalent pipeline
- [ ] Integration: `cd subdir && /BIN/cat relative-path`
- [ ] Integration: `export VAR=1` then exec child that reads `VAR` via `getenv`
- [ ] Integration: command on `PATH` runs without `/BIN/` prefix in the typed name

---

## Acceptance criteria

1. **`^C` during `curl` or `ping`** aborts the child; shell remains usable.
2. **Child exit** reaps correctly; no zombie leaks in normal shell use.
3. **Kernel cwd** — `cd` in shell affects child `open("relative")` after `execve`.
4. **Environment** — `execve` delivers non-empty `envp`; child can read `getenv("PATH")` (and at least one custom variable).
5. **`PATH` lookup** — bare command name resolves via `PATH` (default includes `/BIN`); explicit absolute paths still work.
6. **Pipes and redirects** work for at least one pipeline and one output redirect.
7. **`/dev/null`** — writes discarded; reads return EOF.
8. **PID 1** reaps orphans; shell runs as a child of init.
9. **Serial remains the recommended interface** in README; GUI is not required for daily development.

---

## Notes

- GUI input ([phase 14](14-gui.md)) should reuse the same TTY/input dispatch where possible.
- Do not block on procfs; `/proc/self/fd` can come later in [phase 11](11-procfs-and-sysfs.md).
- Framebuffer text mode is optional here or early in phase 14 — mouse/windows are not required.
