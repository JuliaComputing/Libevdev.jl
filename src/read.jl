using FileWatching: poll_fd

const _EAGAIN = Int(Base.Libc.EAGAIN)

# Maximum interval between `isopen` re-checks while parked in `poll_fd`.
# Bounds the latency at which a `read_event(; block=true)` call observes
# a concurrent `close(dev)` from another task and returns.
const _BLOCK_POLL_TIMEOUT_S = 0.1

"""
    read_event(dev; block=true) -> Union{InputEvent, Nothing}

Read a single event from `dev`.

# Arguments
- `dev::EvdevDevice`: an open device.
- `block::Bool=true`: when `true`, wait until an event is available;
  when `false`, return `nothing` immediately if the device's queue is
  empty.

# Returns
The next [`InputEvent`](@ref), or `nothing` if no event is available —
either because `block=false` was set and the queue was empty, or
because the device was closed while the call was parked.

If the kernel reports `SYN_DROPPED` (the queue overflowed), the
returned event is the `EV_SYN`/`SYN_DROPPED` marker itself; the caller
is responsible for entering SYNC drain mode. Use [`events`](@ref) for
transparent draining.

# Throws
- `EvdevError` for any non-`EAGAIN` error from `libevdev_next_event`.

# Notes
Safe to call from any task. The internal lock is released across the
`poll_fd` wait, leaving other tasks (writers, [`grab`](@ref), ...)
free to proceed against the device while a reader is parked.

Blocking calls use a timed poll with `isopen` re-checks (~100 ms
granularity), so a concurrent `close(dev)` from another task always
unwedges the reader.
"""
function read_event(dev::EvdevDevice; block::Bool=true)
    ev_ref = Ref{InputEvent}()
    while true
        isopen(dev) || return nothing
        status = lock(dev.lock) do
            ccall((:libevdev_next_event, LibEvdev.libevdev),
                  Cint, (Ptr{LibEvdev.libevdev}, Cuint, Ptr{InputEvent}),
                  dev, UInt32(LibEvdev.LIBEVDEV_READ_FLAG_NORMAL), ev_ref)
        end
        if status == Int(LibEvdev.LIBEVDEV_READ_STATUS_SUCCESS)
            return ev_ref[]
        elseif status == Int(LibEvdev.LIBEVDEV_READ_STATUS_SYNC)
            # SYN_DROPPED notice. The event itself is the EV_SYN/SYN_DROPPED
            # marker; the iterator wrapper recognizes it and switches into
            # SYNC drain mode on the next call.
            return ev_ref[]
        elseif status == -_EAGAIN
            block || return nothing
            # Lock was released by the `lock do` block above; do not
            # hold it across the poll, which can park indefinitely.
            # Timed poll guarantees we re-check `isopen` periodically.
            try
                poll_fd(dev.fd, _BLOCK_POLL_TIMEOUT_S; readable=true)
            catch
                # Poll error (fd invalidated, etc.) — loop will re-check
                # isopen and either retry or exit cleanly.
            end
        else
            throw(EvdevError(Int32(-status), "libevdev_next_event"))
        end
    end
end

"""
    EventIterator

Iterator returned by [`events`](@ref). Yields [`InputEvent`](@ref)s from
the wrapped device and handles `SYN_DROPPED` drains transparently so
consumers see a clean stream. Terminates (`iterate` returns `nothing`)
once the device is closed.
"""
struct EventIterator
    dev::EvdevDevice
end

"""
    events(dev::EvdevDevice) -> EventIterator

Construct an iterator over input events from `dev`.

# Returns
An [`EventIterator`](@ref) yielding [`InputEvent`](@ref) values.

# Notes
Typical usage:

    for ev in events(dev)
        # ...
    end

When the kernel's event queue overflows, libevdev emits a
`SYN_DROPPED` notice followed by synthesized state-delta events. The
iterator yields the `SYN_DROPPED` event itself (so consumers can
observe the boundary), then yields the delta events inline before
resuming normal reads — everything flows through the same iterator.
"""
events(dev::EvdevDevice) = EventIterator(dev)

Base.IteratorSize(::Type{EventIterator}) = Base.SizeUnknown()
Base.eltype(::Type{EventIterator}) = InputEvent

# State machine: `:normal` reads with FLAG_NORMAL; on SYN_DROPPED switch
# to `:sync` and drain with FLAG_SYNC until -EAGAIN, then back to :normal.
function Base.iterate(it::EventIterator, state::Symbol=:normal)
    dev = it.dev
    isopen(dev) || return nothing
    try
        if state === :normal
            ev = read_event(dev; block=true)
            ev === nothing && return nothing
            if ev.type == EV_SYN && ev.code == SYN_DROPPED
                return (ev, :sync)
            end
            return (ev, :normal)
        else  # :sync
            ev_ref = Ref{InputEvent}()
            while true
                isopen(dev) || return nothing
                status = lock(dev.lock) do
                    ccall((:libevdev_next_event, LibEvdev.libevdev),
                          Cint, (Ptr{LibEvdev.libevdev}, Cuint, Ptr{InputEvent}),
                          dev, UInt32(LibEvdev.LIBEVDEV_READ_FLAG_SYNC), ev_ref)
                end
                if status == Int(LibEvdev.LIBEVDEV_READ_STATUS_SUCCESS)
                    return (ev_ref[], :sync)
                elseif status == Int(LibEvdev.LIBEVDEV_READ_STATUS_SYNC)
                    # Another sync boundary mid-stream; keep draining.
                    return (ev_ref[], :sync)
                elseif status == -_EAGAIN
                    # Drain complete; resume normal reads.
                    return iterate(it, :normal)
                else
                    throw(EvdevError(Int32(-status), "libevdev_next_event(SYNC)"))
                end
            end
        end
    catch e
        # If the device was closed concurrently, treat as clean EOF.
        # Anything else is a real error and propagates.
        if e isa EvdevError && !isopen(dev)
            return nothing
        end
        if !isopen(dev)
            return nothing
        end
        rethrow()
    end
end

"""
    event_channel(dev::EvdevDevice; size::Integer=64) -> Channel{InputEvent}

Start a background pump that drains [`events(dev)`](@ref) into a buffered
channel.

# Arguments
- `dev::EvdevDevice`: an open device.
- `size::Integer=64`: channel buffer capacity. Larger buffers absorb
  burst latency at the cost of memory and added delivery delay.

# Returns
A `Channel{InputEvent}` that closes when the device closes or the pump
errors. Consumers can iterate with `for ev in ch ... end` and exit
cleanly on teardown.

# Notes
The pump runs on a `Threads.@spawn` task and competes with any other
readers of `dev`. Use this when you want fan-out to one or more channel
consumers; use [`events`](@ref) directly for a single-consumer iterator
in the caller's task.
"""
function event_channel(dev::EvdevDevice; size::Integer=64)
    ch = Channel{InputEvent}(size)
    Threads.@spawn try
        for ev in events(dev)
            put!(ch, ev)
        end
        # Clean exit: iterator returned `nothing`, meaning the device
        # was closed. Consumers will see the channel close below.
        @debug "event_channel pump exiting cleanly (device closed)"
    catch e
        # An unexpected error in the read path. Surface it at @warn so
        # consumers can correlate "my channel suddenly closed" with a
        # cause. A `Channel` can't carry an exception payload, so log
        # is the best we can do.
        @warn "event_channel pump exiting due to error" exception=(e, catch_backtrace())
    finally
        close(ch)
    end
    return ch
end
