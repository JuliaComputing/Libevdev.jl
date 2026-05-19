# Kernel constants

```@meta
CurrentModule = Libev
```

`using Libev` brings the Linux input event-code constants into scope.
A small parser produces them at precompile time directly from
`linux/input-event-codes.h` and `linux/input.h`, and they regenerate
automatically on the next precompile after a kernel-headers upgrade.

## How they're produced

At precompile time `Libev` reads two kernel headers:

- `linux/input-event-codes.h` — the bulk of event-related constants.
- `linux/input.h` — force-feedback effects, multi-touch tool types,
  bus and identity codes.

Each header is resolved independently by checking, in order:

1. `$JULIA_LIBEV_KERNEL_HEADERS/<header>` — the environment-variable
   override (see [Customizing the header source](#customizing-the-header-source)).
2. `/usr/include/linux/<header>` — the standard system path.
3. `/usr/include/x86_64-linux-gnu/linux/<header>` — the multiarch
   system path.
4. `deps/<header>` — a package-bundled copy of the header.

The parser then walks each header line-by-line, matches
`#define NAME EXPR` lines whose name starts with one of the wrapper's
prefix list, and emits `const NAME = EXPR` in the `Libev` module.
`EXPR` covers everything `Meta.parse` accepts: integer literals, hex
literals, simple arithmetic, or aliases to earlier names. The same
regex naturally skips function-like macros, `_IOR`/`_IOW` ioctl macros,
and struct declarations, so the parser handles both headers uniformly.

`include_dependency` on each resolved header path makes Julia rebuild
the precompile cache when a header changes, so a kernel-headers
upgrade flows through on the next precompile.

## Categories

From `<linux/input-event-codes.h>`:

| Prefix | Meaning | Examples |
|--------|---------|----------|
| `EV_*` | Event types | `EV_SYN`, `EV_KEY`, `EV_REL`, `EV_ABS`, `EV_MSC`, `EV_FF` |
| `SYN_*` | Synchronization codes | `SYN_REPORT`, `SYN_DROPPED` |
| `KEY_*` | Keyboard / key codes | `KEY_A`, `KEY_ENTER`, `KEY_LEFTCTRL` |
| `BTN_*` | Non-keyboard buttons | `BTN_LEFT`, `BTN_SOUTH`, `BTN_TRIGGER` |
| `ABS_*` | Absolute axes | `ABS_X`, `ABS_Y`, `ABS_RX`, `ABS_HAT0X`, `ABS_MT_TOOL_TYPE` |
| `REL_*` | Relative axes | `REL_X`, `REL_Y`, `REL_WHEEL` |
| `MSC_*` | Miscellaneous events | `MSC_SCAN`, `MSC_TIMESTAMP` |
| `LED_*` | LED states | `LED_NUML`, `LED_CAPSL` |
| `REP_*` | Auto-repeat parameters | `REP_DELAY`, `REP_PERIOD` |
| `SND_*` | Sound output | `SND_CLICK`, `SND_BELL` |
| `INPUT_PROP_*` | Device property flags | `INPUT_PROP_POINTER`, `INPUT_PROP_DIRECT` |
| `SW_*` | Switch states | `SW_LID`, `SW_TABLET_MODE` |

From `<linux/input.h>`:

| Prefix | Meaning | Examples |
|--------|---------|----------|
| `FF_*` | Force-feedback codes for `EV_FF` events | `FF_RUMBLE`, `FF_PERIODIC`, `FF_GAIN`, `FF_AUTOCENTER` |
| `MT_TOOL_*` | Multi-touch tool types — values for `ABS_MT_TOOL_TYPE` events | `MT_TOOL_FINGER`, `MT_TOOL_PEN`, `MT_TOOL_PALM` |
| `BUS_*` | Bus types — values returned by [`bustype`](@ref) | `BUS_USB`, `BUS_PCI`, `BUS_BLUETOOTH` |
| `ID_*` | Indices into the kernel `input_id[4]` identity array (rarely needed; use [`vendor_id`](@ref) etc. instead) | `ID_BUS`, `ID_VENDOR`, `ID_PRODUCT`, `ID_VERSION` |

## Usage

These constants are plain `UInt8`/`UInt16`/`Int` integers. They appear
as the `type` and `code` fields of an [`InputEvent`](@ref), and as
arguments to [`has_event`](@ref), [`abs_info`](@ref),
[`write_event`](@ref), etc.:

```julia
ev.type == EV_KEY && ev.code == KEY_A    # the A key was pressed/released
has_event(dev, EV_ABS, ABS_X)            # device has an X axis
write_event(u, EV_KEY, KEY_A, 1)         # synthesize an A press
axis(tracker, ABS_X)                     # current X value
```

## Customizing the header source

To use headers from a custom kernel tree, set
`JULIA_LIBEV_KERNEL_HEADERS` to a directory containing
`input-event-codes.h` and `input.h`:

```sh
JULIA_LIBEV_KERNEL_HEADERS=/path/to/my/linux-headers/include/linux \
    julia --project -e 'using Pkg; Pkg.precompile(strict=true)'
```

Libev pulls each header from this directory, then the system path,
then the multiarch system path, then the bundled `deps/` copy — see
the full search order above. Each header is resolved against the chain
independently, so an override directory containing one of the two
still works for the whole pair: the other comes from the system path
or `deps/`.

Precompile caches must be manually invalidated when the environment
variable changes. After setting or modifying
`JULIA_LIBEV_KERNEL_HEADERS`, force a rebuild with
`Pkg.precompile(strict=true)` or delete `~/.julia/compiled/v*/Libev`.
