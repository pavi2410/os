# Phase 8 — Process environment

**Goal:** Make processes, the serial console, environment, and basic IPC behave like a Unix-like OS — before virtual memory expansion and new filesystems.

**Depends on:** [Phase 7 — Copy-on-write fork](07-copy-on-write-fork.md) (cheap fork helps pipes and job control)

**Unlocks:** [Phase 9 — Virtual memory and page cache](09-virtual-memory-and-page-cache.md), [Phase 14 — GUI](14-gui.md) (input/event path)

---

## Rationale

Interaction today is entirely over **serial**: shell, `curl` output, kernel panics. Several correctness gaps block “normal” Unix behavior:

- ~~`cd`/`pwd` are **shell-local**~~ — kernel `chdir`/`getcwd` and shell wrappers (done)
- ~~No **environment variables**~~ — `execve` delivers `envp`; shell `export` and `PATH` lookup (done)
- ~~No **`PATH`**~~ — shell searches colon-separated `PATH` (done)
- ~~No **pipes** or FD duplication~~ — `pipe` syscall, shell `|` pipelines, `>` / `2>&1` redirects (done)
- ~~**Init is the shell**~~ — `/BIN/INIT` is PID 1; shell runs as its child (done)
- ~~No **`/dev`** nodes~~ — kernel devfs exposes `/dev/null`, `/dev/zero`, `/dev/ttyS0` (done)

Polish this layer before `mmap`, ext2, and SMP.

---

## Checklist

### TTY / console

- [x] Document serial as primary console (`/dev/ttyS0` or equivalent) — open `/dev/ttyS0` for read/write on the serial TTY
- [ ] Review [`drivers/tty.zig`](../../kernel/drivers/tty.zig) — echo, erase, canonical mode edge cases
- [ ] ANSI: verify common sequences used by tools (`curl`, future pagers)
- [ ] TTY ioctls or minimal equivalents (`tcsetattr` subset)
- [ ] Clearer stderr vs stdout semantics

### devfs (minimal)

- [x] Pseudo filesystem or static device nodes under `/dev`
- [x] `/dev/null`, `/dev/zero`
- [x] `/dev/ttyS0` (or console device) openable from user programs
- [x] Mount or populate `/dev` at boot (init or kernel thread)

### Kernel working directory

- [x] Per-process cwd in [`proc/process.zig`](../../kernel/proc/process.zig)
- [x] Syscalls: `chdir`, `getcwd`
- [x] Wire cwd into VFS path resolution (`open`, `stat`, `unlink`, `mkdir`, …)
- [x] Migrate shell `cd`/`pwd` to syscalls (remove shell-only cwd or keep as thin wrapper)
- [x] Integration: shell `cd` → fork/exec child opens relative path correctly

### Environment variables and PATH

#### Kernel / loader

- [x] Parse `envp` in `sysExecve` ([`handlers.zig`](../../kernel/syscall/handlers.zig)) — stop ignoring the third argument
- [x] Store environ per process in [`proc/process.zig`](../../kernel/proc/process.zig) (pointer list or contiguous strings in user memory)
- [x] Extend [`pushInitialStack`](../../kernel/mm/user_loader.zig) to place **envp strings + pointers** on the user stack per SysV ABI
- [x] `fork` copies parent environ to child (same rules as Linux: shared until written — COW from [phase 7](07-copy-on-write-fork.md) applies once pages are mapped)
- [x] `execve` replaces environ entirely with the new `envp`
- [x] Document max env count / total env bytes (bounded, like argv limits today)

#### Shell

- [x] In-process environ table (e.g. `KEY=value` strings, `export` builtin)
- [x] Default at startup: at least `PATH=/BIN`, `PWD=/` (or sync `PWD` with cwd)
- [x] Optional defaults: `HOME=/`, `SHELL=/BIN/SHELL` — document chosen values
- [x] `export NAME=value` and `export NAME` (inherit from shell table)
- [x] Pass full environ to `execve` (replace empty [`exec_envp`](../../userspace/shell/cmd/run.zig))
- [x] **`PATH` lookup** — for bare command names, search colon-separated directories in order
- [x] Still support explicit paths (`/BIN/curl`, `./tool` once cwd is kernel-side)
- [x] Uppercase FAT 8.3 names: document whether `PATH` entries are normalized or `/BIN` stays canonical

#### Userspace ulib (minimal)

- [x] `getenv(name)` — scan process environ on stack or via future syscall stub
- [ ] Optional: `setenv` / `putenv` for shell and tests (can be shell-only at first)

#### Tests

- [x] Integration: `export FOO=bar`, run stub or shell builtin child that prints `FOO`
- [x] Integration: `PATH=/BIN` (or multi-dir once second dir exists) — bare `curl` resolves without hardcoded prefix in `run.zig`
- [x] Host or integration: `execve` with non-empty `envp` — child stack contains expected strings

### IPC and file descriptors

- [x] `pipe` / `pipe2` — ring buffer between two FDs
- [x] `dup`, `dup2` — FD table manipulation (no `fcntl(F_DUPFD)` yet)
- [x] Shell pipelines: `ls | wc` (even if `wc` is a stub)
- [x] Shell redirects: `>`, `>>`, `2>`, `2>>`, `2>&1`, `<` (no heredocs)
- [x] `fork` inherits pipe FDs correctly; `execve` preserves them

### Signals (minimal Linux subset)

- [x] Signal numbers and `sigaction` table per process (`SIG_DFL` / `SIG_IGN` only)
- [x] Deliver `SIGCHLD` to parent on child exit
- [x] Deliver `SIGINT` on serial break or `^C` equivalent (foreground child via `fg_pid`)
- [x] Syscalls: `rt_sigaction`, `rt_sigprocmask`, `kill` (smallest viable subset)
- [x] Default dispositions: terminate, ignore, stop — document deviations from Linux

### Init / PID 1

- [x] Separate **init process** from interactive shell (e.g. `/BIN/init` or kernel-launched stub)
- [x] PID 1 `wait` loop — reap orphaned children
- [x] Init spawns shell (or getty) as a child, not as init itself
- [x] Document boot chain: kernel → init → shell

### Shell integration

- [x] Shell ignores `SIGINT` while running builtins; child receives `SIGINT`
- [ ] Optional: background jobs (`cmd &`, `fg`, `bg`) — stretch goal

### Process groups / sessions (stretch)

- [ ] `setpgid`, `setsid` — only if job control is pursued
- [ ] Controlling terminal concept for serial

### Tests

- [ ] Integration: `^C` during `curl` or `ping`; shell returns to prompt
- [x] Integration: child exit wakes blocked parent (`wait4`)
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
6. **Pipes and redirects** work for at least one pipeline and one output redirect. ✅
7. **`/dev/null`** — writes discarded; reads return EOF.
8. **PID 1** reaps orphans; shell runs as a child of init. ✅
9. **Serial remains the recommended interface** in README; GUI is not required for daily development.

---

## Notes

- **Boot chain:** kernel → [`init_launch.zig`](../../kernel/proc/init_launch.zig) loads `/BIN/INIT` as PID 1 → init forks/execs `/BIN/SHELL` and reaps with `wait(-1)`. Orphans of dead parents are reparented to PID 1 in the kernel.
- GUI input ([phase 14](14-gui.md)) should reuse the same TTY/input dispatch where possible.
- Do not block on procfs; `/proc/self/fd` can come later in [phase 11](11-procfs-and-sysfs.md).
- Framebuffer text mode is optional here or early in phase 14 — mouse/windows are not required.
- **Signals (phase 8):** only `SIG_DFL` and `SIG_IGN` via `rt_sigaction`; no user handler frames / `rt_sigreturn` yet. Foreground process tracking uses `fg_pid` on the serial TTY until `setpgid` / job control. `SIGCHLD` is delivered but defaults to ignore. `SIGSTOP` is not implemented.
