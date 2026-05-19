# Libev.jl

A Julian wrapper around [libevdev](https://www.freedesktop.org/wiki/Software/libevdev/),
the Linux input-device userspace library. Read events from real input
devices, synthesize events on virtual ones (uinput), and track absolute-axis
state from a background task.

## Quick tour

Read keyboard events:

```julia
using Libev

open(EvdevDevice, "/dev/input/event3") do dev
    @info "device" name=name(dev) vendor=vendor_id(dev) product=product_id(dev)
    for ev in events(dev)
        ev.type == EV_KEY && println("key=", ev.code, " value=", ev.value)
    end
end
```

Track a joystick's current axis state from any task:

```julia
t = AxisTracker("/dev/input/event10")
try
    while true
        @info "stick" x=axis(t, ABS_X) y=axis(t, ABS_Y)
        sleep(0.05)
    end
finally
    close(t)
end
```

Synthesize a key press through uinput:

```julia
open(EvdevDevice, "/dev/input/event3") do template
    u = UinputDevice(template)
    try
        write_event(u, EV_KEY, KEY_A, 1); syn(u)   # press
        write_event(u, EV_KEY, KEY_A, 0); syn(u)   # release
    finally
        close(u)
    end
end
```

## Contents

- [Devices](devices.md) — opening devices, identity, capabilities, lifecycle.
- [Reading events](reading.md) — `read_event`, the `events` iterator, `event_channel`.
- [Writing events](writing.md) — `UinputDevice` for synthesizing events.
- [Axis tracker](tracker.md) — background-pumped absolute-axis state.
- [Kernel constants](constants.md) — `EV_*`, `KEY_*`, `BTN_*`, `ABS_*`, ...
- [Internals](internals.md) — the generated bindings layer.

## Threading model

An [`EvdevDevice`](@ref) or [`UinputDevice`](@ref) can be shared
across tasks and threads freely; per-handle `ReentrantLock`s serialize
every call into the underlying single-threaded libevdev library.

[`AxisTracker`](@ref) is designed for high-rate polling — a background
watcher task updates `Threads.Atomic{Int32}` slots from the event
stream, and the [`axis`](@ref) / [`axis_values`](@ref) queries are
lock-free atomic loads against those slots.
