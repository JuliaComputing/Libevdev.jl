"""
    UinputDevice

Virtual input device created from a template [`EvdevDevice`](@ref).
Inherits the template's capabilities, identity, and absinfo, then
exposes a write API for injecting events into the kernel input
subsystem (events appear to userspace as if from a real input device).

Thread-safe: all operations acquire an internal lock before touching
the underlying C handle.

# Lifecycle
Construct with [`UinputDevice(template)`](@ref). Always [`close`](@ref)
when done. The handle owns a managed `/dev/uinput` fd that is released
on close; a GC finalizer also closes the handle as a backstop, but
explicit `close` removes the virtual device immediately while the
finalizer waits for the next collection.

# Operations
- Inject events: [`write_event`](@ref).
- Flush a batch of events to consumers: [`syn`](@ref).
- Discover the kernel-assigned paths: [`syspath`](@ref), [`devnode`](@ref).
"""
mutable struct UinputDevice
    ptr::Ptr{LibevdevRaw.libevdev_uinput}
    lock::ReentrantLock
    closed::Bool
end

function _finalize_uinput!(u::UinputDevice)
    try
        close(u)
    catch
    end
    return nothing
end

"""
    UinputDevice(template::EvdevDevice) -> UinputDevice

Create a virtual input device cloning the capabilities, identity, and
absinfo of `template`.

# Arguments
- `template::EvdevDevice`: the device whose configuration to mirror.
  May be freed after the call returns — libevdev copies the state.

# Returns
A live `UinputDevice` ready to accept [`write_event`](@ref) calls.

# Throws
- `EvdevError` if the kernel call fails. The most common cause is
  `EACCES`: the process lacks permission to open `/dev/uinput` (root
  or membership in a suitable group is required on most systems).

# Notes
The underlying `/dev/uinput` fd is opened and managed by libevdev
(`LIBEVDEV_UINPUT_OPEN_MANAGED`) and is closed by [`close`](@ref).
"""
function UinputDevice(template::EvdevDevice)
    ref = Ref{Ptr{LibevdevRaw.libevdev_uinput}}(C_NULL)
    rc = lock(template.lock) do
        ccall((:libevdev_uinput_create_from_device, _libevdev_so),
              Cint,
              (Ptr{LibevdevRaw.libevdev}, Cint, Ptr{Ptr{LibevdevRaw.libevdev_uinput}}),
              template, Cint(LibevdevRaw.LIBEVDEV_UINPUT_OPEN_MANAGED), ref)
    end
    if rc != 0
        throw(EvdevError(Int32(-rc), "libevdev_uinput_create_from_device"))
    end
    u = UinputDevice(ref[], ReentrantLock(), false)
    finalizer(_finalize_uinput!, u)
    return u
end

"""
    close(u::UinputDevice)

Destroy the uinput handle, releasing the managed kernel fd and removing
the virtual device from the input subsystem. Idempotent.

After `close`, any operation on `u` other than `close` / `isopen`
throws.
"""
function Base.close(u::UinputDevice)
    if u.closed
        return nothing
    end
    u.closed = true
    p = u.ptr
    u.ptr = C_NULL
    if p != C_NULL
        ccall((:libevdev_uinput_destroy, _libevdev_so),
              Cvoid, (Ptr{LibevdevRaw.libevdev_uinput},), p)
    end
    return nothing
end

"""
    isopen(u::UinputDevice) -> Bool

`true` until [`close`](@ref) has been called.
"""
Base.isopen(u::UinputDevice) = !u.closed

# Allow passing a UinputDevice directly to ccalls expecting
# Ptr{libevdev_uinput}; unsafe_convert is the closed-check gate.
Base.cconvert(::Type{Ptr{LibevdevRaw.libevdev_uinput}}, u::UinputDevice) = u
function Base.unsafe_convert(::Type{Ptr{LibevdevRaw.libevdev_uinput}}, u::UinputDevice)
    u.closed && error("UinputDevice is closed")
    return u.ptr
end

"""
    write_event(u::UinputDevice, type::Integer, code::Integer, value::Integer)

Inject a single input event into the virtual device.

# Arguments
- `u`: the open uinput device.
- `type`: event type (`EV_KEY`, `EV_ABS`, `EV_REL`, ...).
- `code`: type-specific code (`KEY_A`, `BTN_LEFT`, `ABS_X`, ...).
- `value`: type-specific value (key state, axis position, ...).

# Returns
`nothing`.

# Throws
- `EvdevError` if the kernel write fails.

# Notes
Events accumulate in a kernel-side batch until [`syn`](@ref) submits
the batch for delivery to consumers. Every logical input action (e.g.
a key press) must end with a `syn` call to be observed.
"""
function write_event(u::UinputDevice, type::Integer, code::Integer, value::Integer)
    lock(u.lock) do
        rc = ccall((:libevdev_uinput_write_event, _libevdev_so),
                   Cint,
                   (Ptr{LibevdevRaw.libevdev_uinput}, Cuint, Cuint, Cint),
                   u, UInt32(type), UInt32(code), Int32(value))
        check(rc, "libevdev_uinput_write_event")
    end
    return nothing
end

"""
    write_event(u::UinputDevice, ev::InputEvent)

Convenience overload that injects the `type`/`code`/`value` fields of
`ev`. The timestamp fields of `ev` are ignored — the kernel stamps
events as they're delivered.
"""
write_event(u::UinputDevice, ev::InputEvent) =
    write_event(u, ev.type, ev.code, ev.value)

"""
    syn(u::UinputDevice)

Emit an `EV_SYN`/`SYN_REPORT` event, flushing the current batch of
[`write_event`](@ref) calls to consumers. Every logical input action
(e.g. a key press) must be followed by `syn` for it to be observed.
"""
syn(u::UinputDevice) = write_event(u, EV_SYN, SYN_REPORT, 0)

"""
    syspath(u::UinputDevice) -> Union{String, Nothing}

Return the `/sys` path of the created virtual device.

# Returns
The sysfs path as a `String`, or `nothing` if libevdev cannot determine
it (older kernels or sysfs not mounted).
"""
function syspath(u::UinputDevice)
    p = lock(u.lock) do
        ccall((:libevdev_uinput_get_syspath, _libevdev_so),
              Ptr{Cchar}, (Ptr{LibevdevRaw.libevdev_uinput},), u)
    end
    return p == C_NULL ? nothing : unsafe_string(p)
end

"""
    devnode(u::UinputDevice) -> Union{String, Nothing}

Return the `/dev/input/eventN` device node path corresponding to the
created virtual device.

# Returns
The device node path as a `String`, or `nothing` if libevdev cannot
determine it.
"""
function devnode(u::UinputDevice)
    p = lock(u.lock) do
        ccall((:libevdev_uinput_get_devnode, _libevdev_so),
              Ptr{Cchar}, (Ptr{LibevdevRaw.libevdev_uinput},), u)
    end
    return p == C_NULL ? nothing : unsafe_string(p)
end
