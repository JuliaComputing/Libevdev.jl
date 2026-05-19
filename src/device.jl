"""
    EvdevDevice

Handle to a Linux input device (typically `/dev/input/eventN`).

Thread-safe: all operations acquire an internal lock before touching the
underlying C handle, so the same device can be used from multiple tasks
concurrently.

# Lifecycle
Construct with [`EvdevDevice(path)`](@ref) or
[`EvdevDevice(fd; owns_fd)`](@ref). Always [`close`](@ref) the device
when done, either explicitly or via the `open(... do dev ... end)` form.
A GC finalizer also calls `close` as a backstop; explicit `close`
releases the fd immediately, while the finalizer waits for the next
collection.

# What you can do with it
- Read events: [`read_event`](@ref), [`events`](@ref), [`event_channel`](@ref).
- Query identity / capabilities: [`name`](@ref), [`vendor_id`](@ref),
  [`has_event`](@ref), [`has_property`](@ref), [`abs_info`](@ref), ...
- Take exclusive access: [`grab`](@ref) / [`ungrab`](@ref).
- Track absolute axes: pass to [`AxisTracker`](@ref).
"""
mutable struct EvdevDevice
    ptr::Ptr{LibEvdev.libevdev}
    fd::RawFD
    owns_fd::Bool
    lock::ReentrantLock
    closed::Bool
end

# Finalizer-safe wrapper around `close`. Finalizers must not throw.
function _finalize_device!(dev::EvdevDevice)
    try
        close(dev)
    catch
    end
    return nothing
end

"""
    EvdevDevice(path::AbstractString) -> EvdevDevice

Open the input device at `path` and wrap it in a libevdev handle.

# Arguments
- `path`: filesystem path to the device (e.g. `/dev/input/event3`).

# Returns
A live `EvdevDevice` that owns the underlying fd and will close it on
[`close`](@ref) / GC finalization.

# Throws
- `SystemError` if `open(2)` fails (nonexistent path, EACCES, ...).
- `EvdevError` if `libevdev_new_from_fd` fails on the opened fd.
"""
function EvdevDevice(path::AbstractString)
    # libevdev assumes the fd is non-blocking; open it that way.
    flags = Base.Filesystem.JL_O_RDONLY | Base.Filesystem.JL_O_NONBLOCK
    raw = ccall(:open, Cint, (Cstring, Cint), path, flags)
    if raw < 0
        throw(Base.SystemError("open($(repr(path)))", Libc.errno()))
    end
    fd = RawFD(raw)
    ref = Ref{Ptr{LibEvdev.libevdev}}(C_NULL)
    rc = LibEvdev.libevdev_new_from_fd(raw, ref)
    if rc < 0
        # Clean up on partial construction so no fd escapes.
        ccall(:close, Cint, (Cint,), raw)
        throw(EvdevError(Int32(-rc), "libevdev_new_from_fd($(repr(path)))"))
    end
    dev = EvdevDevice(ref[], fd, true, ReentrantLock(), false)
    finalizer(_finalize_device!, dev)
    return dev
end

"""
    EvdevDevice() -> EvdevDevice

Create a synthetic device with no attached file descriptor — a blank
libevdev handle suitable as a template for [`UinputDevice`](@ref).

Configure the device with [`set_name!`](@ref), [`set_vendor_id!`](@ref),
[`enable_event!`](@ref), and friends, then pass it to
`UinputDevice(template)` to materialize a virtual input device with
the configured identity and capabilities.

# Returns
A live `EvdevDevice` with `fd = RawFD(-1)`. Reading APIs
([`read_event`](@ref), [`events`](@ref), [`event_channel`](@ref),
[`AxisTracker`](@ref)) are not meaningful on a synthetic device and
will fail at the `poll_fd` step.

# Throws
- `EvdevError` (with `errno = ENOMEM`) if `libevdev_new` returns NULL.
"""
function EvdevDevice()
    ptr = LibEvdev.libevdev_new()
    ptr == C_NULL && throw(EvdevError(Int32(Libc.ENOMEM), "libevdev_new"))
    dev = EvdevDevice(ptr, RawFD(-1), false, ReentrantLock(), false)
    finalizer(_finalize_device!, dev)
    return dev
end

"""
    EvdevDevice(fd::RawFD; owns_fd::Bool=false) -> EvdevDevice

Wrap an existing file descriptor in a libevdev handle. The caller is
responsible for ensuring `fd` was opened with `O_NONBLOCK`.

# Arguments
- `fd`: open file descriptor referring to an input device.
- `owns_fd`: when `true`, [`close`](@ref) closes the fd as part of
  teardown; when `false` (default), the caller retains ownership of
  the fd and is responsible for closing it.

# Returns
A live `EvdevDevice`.

# Throws
- `EvdevError` if `libevdev_new_from_fd` fails. When `owns_fd=true`,
  the fd is closed before the exception escapes.
"""
function EvdevDevice(fd::RawFD; owns_fd::Bool=false)
    raw = Cint(fd)
    ref = Ref{Ptr{LibEvdev.libevdev}}(C_NULL)
    rc = LibEvdev.libevdev_new_from_fd(raw, ref)
    if rc < 0
        if owns_fd
            ccall(:close, Cint, (Cint,), raw)
        end
        throw(EvdevError(Int32(-rc), "libevdev_new_from_fd(fd=$raw)"))
    end
    dev = EvdevDevice(ref[], fd, owns_fd, ReentrantLock(), false)
    finalizer(_finalize_device!, dev)
    return dev
end

"""
    close(dev::EvdevDevice)

Release the libevdev handle and, if the device owns its fd, close the
fd. Idempotent: subsequent calls (and the GC finalizer) are no-ops.

After `close`, any operation on `dev` other than `close` / `isopen`
throws.
"""
function Base.close(dev::EvdevDevice)
    # Do not acquire dev.lock here: finalizers can run on any thread and
    # acquiring a ReentrantLock from a finalizer context is unsafe. The
    # closed flag plus single-writer teardown makes this race-free.
    if dev.closed
        return nothing
    end
    dev.closed = true
    p = dev.ptr
    dev.ptr = C_NULL
    if p != C_NULL
        LibEvdev.libevdev_free(p)
    end
    if dev.owns_fd
        ccall(:close, Cint, (Cint,), Cint(dev.fd))
    end
    return nothing
end

"""
    isopen(dev::EvdevDevice) -> Bool

`true` until [`close`](@ref) has been called.
"""
Base.isopen(dev::EvdevDevice) = !dev.closed

"""
    open(EvdevDevice, path) -> EvdevDevice
    open(f, EvdevDevice, path)

Alias for [`EvdevDevice(path)`](@ref). The second form is a do-block
scope that closes the device after `f` returns or throws.
"""
Base.open(::Type{EvdevDevice}, path::AbstractString) = EvdevDevice(path)

function Base.open(f::Function, ::Type{EvdevDevice}, path::AbstractString)
    dev = EvdevDevice(path)
    try
        return f(dev)
    finally
        close(dev)
    end
end

# Allow passing an EvdevDevice directly to ccalls expecting Ptr{libevdev}.
# `unsafe_convert` is the only validation gate on the ccall fast path.
Base.cconvert(::Type{Ptr{LibEvdev.libevdev}}, dev::EvdevDevice) = dev
function Base.unsafe_convert(::Type{Ptr{LibEvdev.libevdev}}, dev::EvdevDevice)
    dev.closed && error("EvdevDevice is closed")
    return dev.ptr
end
