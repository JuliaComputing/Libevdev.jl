# Core value types and error handling. No LibEvdev dependency — safe to
# load standalone.

"""
    InputEvent

A single input event from a device, mirroring the Linux kernel's
`struct input_event`. Returned by [`read_event`](@ref) and yielded by
[`events`](@ref).

# Fields
- `sec::Clong`   — event timestamp, seconds component.
- `usec::Clong`  — event timestamp, microseconds component.
- `type::UInt16` — event type (`EV_KEY`, `EV_ABS`, `EV_REL`, `EV_SYN`, ...).
- `code::UInt16` — type-specific code (`KEY_A`, `BTN_LEFT`, `ABS_X`, ...).
- `value::Int32` — type-specific value (key state, axis position, ...).
"""
struct InputEvent
    sec::Clong
    usec::Clong
    type::UInt16
    code::UInt16
    value::Int32
end

# Layout matches `struct input_event` on Linux x86_64 (timeval is two
# longs, then u16/u16/s32). isbits, so a Ref{InputEvent} is sufficient
# as the output buffer for libevdev_next_event.

"""
    EvdevError(errno, what)

Thrown when a libevdev call fails.

# Fields
- `errno::Int32` — the (positive) errno value reported by the call.
- `what::String` — short label identifying the call site.

# Display
`showerror` prints `EvdevError: <what>: <strerror(errno)>`.
"""
struct EvdevError <: Exception
    errno::Int32
    what::String
end

function Base.showerror(io::IO, e::EvdevError)
    print(io, "EvdevError: ", e.what, ": ", Libc.strerror(e.errno))
end

# Internal: libevdev returns the negation of errno on error. `check`
# throws an EvdevError when rc < 0 and is the funnel every Cint-returning
# wrapper pipes its return through.
@inline function check(rc::Integer, what::AbstractString)
    if rc < 0
        throw(EvdevError(Int32(-rc), String(what)))
    end
    return rc
end
