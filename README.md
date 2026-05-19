# Libevdev.jl

A Julian wrapper around [libevdev](https://www.freedesktop.org/wiki/Software/libevdev/),
the Linux input-device userspace library. Read events from real input
devices (keyboards, mice, joysticks, gamepads, tablets), synthesize
events on virtual devices via uinput, and track absolute-axis state
from a background task.

Linux-only. The libevdev binary ships through `libevdev_jll`, so the
package works on any Linux host without a system libevdev install.

## Install

```julia
using Pkg
Pkg.develop(path="path/to/Libevdev")
```

## Quick examples

Read keyboard events:

```julia
using Libevdev

open(EvdevDevice, "/dev/input/event3") do dev
    @info "device" name=name(dev) vendor=vendor_id(dev)
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

## Threading

An `EvdevDevice` or `UinputDevice` can be shared across tasks and
threads freely; per-handle `ReentrantLock`s serialize every call into
the underlying single-threaded libevdev library.

`AxisTracker` is designed for high-rate polling — a background watcher
task updates atomic slots from the event stream, and the `axis` /
`axis_values` queries are lock-free atomic loads against those slots.
