# Internals

This page documents the relationship between the wrapper layer and the
underlying generated bindings — implementation context for contributors
and curious users.

## Bindings module

The `Libevdev.LibevdevRaw` submodule (in `src/LibevdevRaw.jl`) is generated from
the libevdev headers by Clang.jl and contains the raw C API — opaque
`mutable struct libevdev`/`libevdev_uinput` placeholder types, all the
`libevdev_*` `ccall` wrappers, and the `@cenum`-defined enums.

For bindings the wrapper layer omits, call into the submodule directly
as `Libevdev.LibevdevRaw.libevdev_*`. You are then responsible for locking,
lifecycle, and Julia-vs-C type conversion.

Regenerate with:

```sh
julia --project=gen gen/generator.jl
```

## Kernel constants

The `EV_*`, `KEY_*`, `BTN_*`, `ABS_*`, `FF_*`, `MT_TOOL_*`, `BUS_*`,
`ID_*`, etc. constants are emitted directly into `Libevdev` at precompile
time by a small parser (`src/parse_event_codes.jl`) that reads
`/usr/include/linux/input-event-codes.h` and `/usr/include/linux/input.h`,
with bundled fallbacks in `deps/`. See [Kernel constants](constants.md)
for details.

## Wrapper layout

| File | Purpose |
|------|---------|
| `src/types.jl` | [`InputEvent`](@ref), [`EvdevError`](@ref), internal `check` helper. |
| `src/device.jl` | [`EvdevDevice`](@ref) lifecycle, fd ownership, lock. |
| `src/read.jl` | [`read_event`](@ref), [`events`](@ref), [`event_channel`](@ref). |
| `src/uinput.jl` | [`UinputDevice`](@ref) and its write API. |
| `src/props.jl` | Identity / capability / `abs_info` accessors. |
| `src/axis_tracker.jl` | [`AxisTracker`](@ref) and its background pump. |
| `src/parse_event_codes.jl` | Precompile-time parser for the kernel constants header. |
| `src/Libevdev.jl` | Top-level module — assembly + precompile-time codes parse + exports. |

## Concurrency invariants

- Every `ccall` against a `Ptr{libevdev}` or `Ptr{libevdev_uinput}`
  runs inside the corresponding handle's lock.
- The lock is *released* across `FileWatching.poll_fd` waits, leaving
  the device free for writers (and [`grab`](@ref) calls) while a
  reader is parked.
- [`AxisTracker`](@ref) queries are lock-free: each axis is a
  `Threads.Atomic{Int32}` slot, read with an atomic load.
- `close` runs without acquiring the lock, since finalizers can fire
  on any thread and lock acquisition from a finalizer is unsafe;
  idempotency comes from a `closed` flag instead.
