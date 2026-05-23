const _ABS_CODE_RANGE = UInt16(0):UInt16(ABS_MAX)
const _REL_CODE_RANGE = UInt16(0):UInt16(REL_MAX)

"""
    AxisRange(minimum, maximum, fuzz, flat, resolution)

Static metadata for one absolute axis, captured at [`AxisTracker`](@ref)
construction from the kernel's `EVIOCGABS` ioctl. All fields are `Int32`.

# Fields
- `minimum`, `maximum` — the axis's reported range.
- `fuzz` — noise threshold; the driver filters out changes smaller
  than this before they reach userspace.
- `flat` — dead-zone size around the resting position.
- `resolution` — units per millimeter (for spatial axes) or per radian
  (for rotational axes); 0 if unknown.
"""
struct AxisRange
    minimum::Int32
    maximum::Int32
    fuzz::Int32
    flat::Int32
    resolution::Int32
end

"""
    AxisTracker

A background-pumped view of an input device's current axis state,
designed for high-rate polling from any task.

A tracker spawns a `Threads.@spawn` watcher task that drains events
from the underlying [`EvdevDevice`](@ref) and updates atomic slots for
two event classes:

- **`EV_ABS` (absolute axes)** — each slot holds the *latest reported
  value*, overwritten on every event. Use for joystick positions,
  touch coordinates, tablet pen pressure.
- **`EV_REL` (relative axes)** — each slot holds the *cumulative sum
  of deltas* since the tracker was constructed (or the slot was last
  consumed). Use for mouse motion, scroll wheel ticks.

All queries are lock-free atomic loads, so callers can poll at any
rate without contending with the watcher or each other.

# Lifecycle
Construct with [`AxisTracker(path)`](@ref) or
[`AxisTracker(dev; own)`](@ref). Always [`close`](@ref) when done. The
GC finalizer also closes the tracker.

# Absolute-axis API
- Latest value of one axis: [`axis`](@ref).
- Snapshot of all axes: [`axis_values`](@ref).
- Static range metadata: [`axis_range`](@ref), [`axis_codes`](@ref).

# Relative-axis API
- Cumulative delta on one axis: [`rel`](@ref).
- Snapshot of all relative axes: [`rel_values`](@ref).
- Codes followed: [`rel_codes`](@ref).
- Consume-and-reset (read the delta since last consume): [`consume_rel!`](@ref), [`consume_rel_values!`](@ref).

# Limitations
Multi-touch (`MT_*`) axes are tracked, but values are conflated across
touch slots — the tracker keeps one slot per code. For per-touch
state, drive the slot API on the underlying device directly.
"""
mutable struct AxisTracker
    device::EvdevDevice
    owns_device::Bool
    ranges::Dict{UInt16, AxisRange}
    abs_values::Dict{UInt16, Threads.Atomic{Int32}}
    rel_values::Dict{UInt16, Threads.Atomic{Int32}}
    task::Union{Task, Nothing}
    stopping::Threads.Atomic{Bool}
    closed::Bool
end

# Walk the kernel's ABS code range and pick up every axis the device
# advertises. Each axis is seeded with libevdev's cached current value
# so queries return a sane number before any new event has arrived.
function _discover_abs_axes(dev::EvdevDevice)
    ranges = Dict{UInt16, AxisRange}()
    values = Dict{UInt16, Threads.Atomic{Int32}}()
    has_event(dev, Int(EV_ABS)) || return ranges, values
    for code in _ABS_CODE_RANGE
        has_event(dev, Int(EV_ABS), Int(code)) || continue
        info = abs_info(dev, code)
        ranges[code] = AxisRange(Int32(info.minimum), Int32(info.maximum),
                                 Int32(info.fuzz), Int32(info.flat),
                                 Int32(info.resolution))
        v = lock(dev.lock) do
            LibevdevRaw.libevdev_get_event_value(dev, Cuint(EV_ABS), Cuint(code))
        end
        values[code] = Threads.Atomic{Int32}(Int32(v))
    end
    return ranges, values
end

# Walk the kernel's REL code range and pick up every relative axis the
# device advertises. Relative axes report deltas, so each slot starts
# at 0 and accumulates as events arrive.
function _discover_rel_axes(dev::EvdevDevice)
    values = Dict{UInt16, Threads.Atomic{Int32}}()
    has_event(dev, Int(EV_REL)) || return values
    for code in _REL_CODE_RANGE
        has_event(dev, Int(EV_REL), Int(code)) || continue
        values[code] = Threads.Atomic{Int32}(Int32(0))
    end
    return values
end

"""
    AxisTracker(dev::EvdevDevice; own::Bool=false) -> AxisTracker

Wrap an open device and start a background pump task that tracks every
`EV_ABS` axis the device advertises.

# Arguments
- `dev`: an open [`EvdevDevice`](@ref).
- `own`: when `true`, the tracker takes ownership of `dev` and will
  close it on [`close`](@ref); when `false` (default), the caller
  retains ownership and is responsible for closing `dev` after the
  tracker.

# Returns
A live `AxisTracker` whose pump task is already running.

# Throws
Any exception raised while discovering axes (notably `EvdevError` from
[`abs_info`](@ref) on a misbehaving device).

# Notes
Each axis slot is seeded with libevdev's *cached* current value at
construction time. For axes the device hasn't reported a position for
yet (most absolute devices are quiescent until the first user input),
that cached value will be `0`. The first real event updates the slot.
If you need a guaranteed-correct initial value, wait for an event
before querying.
"""
function AxisTracker(dev::EvdevDevice; own::Bool=false)
    ranges, abs_values = _discover_abs_axes(dev)
    rel_values = _discover_rel_axes(dev)
    t = AxisTracker(dev, own, ranges, abs_values, rel_values, nothing,
                    Threads.Atomic{Bool}(false), false)
    finalizer(_finalize_tracker!, t)
    t.task = Threads.@spawn _pump_axes(t)
    return t
end

"""
    AxisTracker(path::AbstractString) -> AxisTracker

Open the device at `path` and wrap it in a tracker that owns it. The
tracker closes the device on [`close`](@ref).

Equivalent to `AxisTracker(EvdevDevice(path); own=true)`.

# Throws
- `SystemError` if `open(2)` fails.
- `EvdevError` if `libevdev_new_from_fd` fails or axis discovery fails.
"""
AxisTracker(path::AbstractString) = AxisTracker(EvdevDevice(path); own=true)

function _finalize_tracker!(t::AxisTracker)
    try
        close(t)
    catch
    end
    return nothing
end

# Pump loop. Inline state machine: NORMAL reads, switch to SYNC drain
# on SYN_DROPPED, back to NORMAL on -EAGAIN. Idle time is parked in a
# *timed* poll_fd so the stopping flag is observed within ~100ms even
# when the device is silent.
function _pump_axes(t::AxisTracker)
    dev = t.device
    ev_ref = Ref{InputEvent}()
    sync_mode = false
    while !t.stopping[]
        isopen(dev) || break
        flag = sync_mode ? UInt32(LibevdevRaw.LIBEVDEV_READ_FLAG_SYNC) :
                           UInt32(LibevdevRaw.LIBEVDEV_READ_FLAG_NORMAL)
        status = try
            lock(dev.lock) do
                ccall((:libevdev_next_event, LibevdevRaw.libevdev),
                      Cint,
                      (Ptr{LibevdevRaw.libevdev}, Cuint, Ptr{InputEvent}),
                      dev, flag, ev_ref)
            end
        catch e
            if t.stopping[] || !isopen(dev)
                @debug "AxisTracker pump exiting: device closed during read"
            else
                @warn "AxisTracker pump exiting due to unexpected exception" exception=(e, catch_backtrace())
            end
            break
        end
        if status == Int(LibevdevRaw.LIBEVDEV_READ_STATUS_SUCCESS)
            _record_event!(t, ev_ref[])
        elseif status == Int(LibevdevRaw.LIBEVDEV_READ_STATUS_SYNC)
            # Either the initial SYN_DROPPED notice or a sync-phase event.
            _record_event!(t, ev_ref[])
            sync_mode = true
        elseif status == -_EAGAIN
            if sync_mode
                sync_mode = false
                continue
            end
            try
                poll_fd(dev.fd, 0.1; readable=true)
            catch
                # Next iteration re-checks `stopping`/`isopen`.
            end
        else
            @warn "AxisTracker pump exiting: libevdev_next_event returned unexpected status" status sync_mode
            break
        end
    end
    return nothing
end

@inline function _record_event!(t::AxisTracker, ev::InputEvent)
    if ev.type == UInt16(EV_ABS)
        # Absolute axes: overwrite with the latest reported value.
        slot = get(t.abs_values, ev.code, nothing)
        slot === nothing || (slot[] = ev.value)
    elseif ev.type == UInt16(EV_REL)
        # Relative axes: accumulate the delta atomically. atomic_add!
        # returns the previous value, which we discard.
        slot = get(t.rel_values, ev.code, nothing)
        slot === nothing || Threads.atomic_add!(slot, ev.value)
    end
    return nothing
end

"""
    close(t::AxisTracker)

Stop the pump task and (if the tracker owns its device) close the
underlying [`EvdevDevice`](@ref). Idempotent.

After `close`, the pump task stops and the tracker no longer records
new events. The slot dictionaries are retained, so [`axis`](@ref),
[`axis_values`](@ref), [`rel`](@ref), and [`rel_values`](@ref)
continue to return the values held at shutdown.

# Notes
Stop is signaled via an atomic flag the pump observes between reads.
Worst-case wait is ~100ms: the pump uses a timed `poll_fd`, so it
wakes at least that often to check the stop flag — including when the
device is silent.
"""
function Base.close(t::AxisTracker)
    t.closed && return nothing
    t.closed = true
    t.stopping[] = true
    if t.task !== nothing
        try
            wait(t.task)
        catch
        end
    end
    if t.owns_device
        try
            close(t.device)
        catch
        end
    end
    return nothing
end

"""
    isopen(t::AxisTracker) -> Bool

`true` until [`close`](@ref) has been called.
"""
Base.isopen(t::AxisTracker) = !t.closed

"""
    axis(t::AxisTracker, code::Integer) -> Int32

Latest observed value of the `ABS_*` axis identified by `code`.

# Arguments
- `code`: an `ABS_*` constant (`ABS_X`, `ABS_RX`, ...).

# Returns
The current axis value as an `Int32`. Safe to call at any rate from
any task — the read is a lock-free atomic load on the slot shared
with the watcher task.

# Throws
- `KeyError` if the device doesn't expose that axis.
"""
axis(t::AxisTracker, code::Integer) = t.abs_values[UInt16(code)][]

"""
    axis_values(t::AxisTracker) -> Dict{UInt16, Int32}

Snapshot of the current value of every tracked axis, keyed by `ABS_*`
code.

# Returns
A new `Dict` mapping axis code to value.

# Notes
Each slot is read atomically, but the snapshot is not transactional
across axes — two axes in the dictionary may reflect values from
slightly different points in time.

Named `axis_values` rather than `axes` to avoid colliding with
`Base.axes` (which would make the export ambiguous for users and
silently turn this into a method extension of the Base function).
"""
function axis_values(t::AxisTracker)
    out = Dict{UInt16, Int32}()
    for (code, slot) in t.abs_values
        out[code] = slot[]
    end
    return out
end

"""
    axis_range(t::AxisTracker, code::Integer) -> AxisRange

Return the static [`AxisRange`](@ref) metadata for an axis: minimum,
maximum, fuzz, flat, resolution. Captured at tracker construction;
unaffected by subsequent events.

# Throws
- `KeyError` if the axis isn't tracked.
"""
axis_range(t::AxisTracker, code::Integer) = t.ranges[UInt16(code)]

"""
    axis_codes(t::AxisTracker) -> Vector{UInt16}

Sorted list of `ABS_*` codes this tracker is following.
"""
axis_codes(t::AxisTracker) = sort!(collect(keys(t.ranges)))

"""
    rel(t::AxisTracker, code::Integer) -> Int32

Cumulative delta on the `REL_*` axis identified by `code`, summed
from every event seen since the tracker was constructed or since the
slot was last consumed via [`consume_rel!`](@ref).

# Arguments
- `code`: a `REL_*` constant (`REL_X`, `REL_Y`, `REL_WHEEL`, ...).

# Returns
The accumulated delta as an `Int32`. Safe to call at any rate from
any task — the read is a lock-free atomic load on the slot shared
with the watcher task.

# Throws
- `KeyError` if the device doesn't expose that relative axis.
"""
rel(t::AxisTracker, code::Integer) = t.rel_values[UInt16(code)][]

"""
    rel_values(t::AxisTracker) -> Dict{UInt16, Int32}

Snapshot of the cumulative delta on every tracked relative axis,
keyed by `REL_*` code.

# Returns
A new `Dict` mapping axis code to accumulated value.

# Notes
Each slot is read atomically, but the snapshot is not transactional
across axes — two axes in the dictionary may reflect deltas summed
to slightly different points in time.
"""
function rel_values(t::AxisTracker)
    out = Dict{UInt16, Int32}()
    for (code, slot) in t.rel_values
        out[code] = slot[]
    end
    return out
end

"""
    rel_codes(t::AxisTracker) -> Vector{UInt16}

Sorted list of `REL_*` codes this tracker is following.
"""
rel_codes(t::AxisTracker) = sort!(collect(keys(t.rel_values)))

"""
    consume_rel!(t::AxisTracker, code::Integer) -> Int32

Atomically read and reset the cumulative delta on the given `REL_*`
axis. Returns the value held in the slot at the moment of the call;
the slot is left at `0` for the next accumulation cycle.

This is the idiomatic primitive for per-frame consumers (game loops,
input controllers) that want "movement since last frame": call
`consume_rel!(t, REL_X)` once per frame and drive your camera or
cursor by the returned delta.

# Throws
- `KeyError` if the device doesn't expose that relative axis.
"""
consume_rel!(t::AxisTracker, code::Integer) =
    Threads.atomic_xchg!(t.rel_values[UInt16(code)], Int32(0))

"""
    consume_rel_values!(t::AxisTracker) -> Dict{UInt16, Int32}

Atomically read and reset every tracked relative axis. Returns a
`Dict` of axis code to accumulated delta at the moment each slot was
swapped; the slots are left at `0`.

# Notes
Each per-axis swap is atomic, but the bulk operation is not
transactional across axes. An event that arrives while
`consume_rel_values!` is iterating may land in the just-reset slot
and show up on the next consume.
"""
function consume_rel_values!(t::AxisTracker)
    out = Dict{UInt16, Int32}()
    for (code, slot) in t.rel_values
        out[code] = Threads.atomic_xchg!(slot, Int32(0))
    end
    return out
end

"""
    tracker_status(t::AxisTracker) -> NamedTuple

Diagnostic snapshot of the tracker's internal state. Useful when
`axis`/`rel` queries return stale values — surfaces whether the
background pump is still running, which axes were discovered, and
the captured pump-task exception if the pump exited.

# Returns
A `NamedTuple` with fields:
- `running::Bool` — whether the pump task is still alive.
- `task_exception` — `nothing` if the task is running or exited
  cleanly, otherwise the exception that killed it.
- `abs_codes::Vector{UInt16}` — `ABS_*` codes discovered at construction.
- `rel_codes::Vector{UInt16}` — `REL_*` codes discovered at construction.
- `closed::Bool` — whether `close(t)` has been called.
"""
function tracker_status(t::AxisTracker)
    running = t.task !== nothing && !istaskdone(t.task)
    task_exception = nothing
    if t.task !== nothing && istaskdone(t.task) && !t.closed
        # Pump exited but we haven't been closed — likely failed.
        try
            wait(t.task)
        catch e
            task_exception = e
        end
    end
    (running        = running,
     task_exception = task_exception,
     abs_codes      = sort!(collect(keys(t.abs_values))),
     rel_codes      = sort!(collect(keys(t.rel_values))),
     closed         = t.closed)
end
