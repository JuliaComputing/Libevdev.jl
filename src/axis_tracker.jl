const _ABS_CODE_RANGE = UInt16(0):UInt16(ABS_MAX)

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

A background-pumped view of an absolute-axis device's current state,
designed for high-rate polling from any task.

A tracker spawns a `Threads.@spawn` watcher task that drains events
from the underlying [`EvdevDevice`](@ref) and writes the latest value
of each `EV_ABS` axis into an atomic slot. The [`axis`](@ref) and
[`axis_values`](@ref) queries read those slots with lock-free atomic
loads, so callers can poll at any rate without contending with the
watcher or each other.

# Lifecycle
Construct with [`AxisTracker(path)`](@ref) or
[`AxisTracker(dev; own)`](@ref). Always [`close`](@ref) when done. The
GC finalizer also closes the tracker.

# Query API
- Latest value of one axis: [`axis`](@ref).
- Snapshot of all axes: [`axis_values`](@ref).
- Static metadata: [`axis_range`](@ref), [`axis_codes`](@ref).

# Limitations
Multi-touch (`MT_*`) axes are tracked, but values are conflated across
touch slots. For proper multi-touch, drive the slot API on the
underlying device directly rather than going through `AxisTracker`.
"""
mutable struct AxisTracker
    device::EvdevDevice
    owns_device::Bool
    ranges::Dict{UInt16, AxisRange}
    values::Dict{UInt16, Threads.Atomic{Int32}}
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
            LibEvdev.libevdev_get_event_value(dev, Cuint(EV_ABS), Cuint(code))
        end
        values[code] = Threads.Atomic{Int32}(Int32(v))
    end
    return ranges, values
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
    ranges, values = _discover_abs_axes(dev)
    t = AxisTracker(dev, own, ranges, values, nothing,
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
        flag = sync_mode ? UInt32(LibEvdev.LIBEVDEV_READ_FLAG_SYNC) :
                           UInt32(LibEvdev.LIBEVDEV_READ_FLAG_NORMAL)
        status = try
            lock(dev.lock) do
                ccall((:libevdev_next_event, LibEvdev.libevdev),
                      Cint,
                      (Ptr{LibEvdev.libevdev}, Cuint, Ptr{InputEvent}),
                      dev, flag, ev_ref)
            end
        catch
            # Device closed mid-read or another terminal condition.
            break
        end
        if status == Int(LibEvdev.LIBEVDEV_READ_STATUS_SUCCESS)
            _record_abs!(t, ev_ref[])
        elseif status == Int(LibEvdev.LIBEVDEV_READ_STATUS_SYNC)
            # Either the initial SYN_DROPPED notice or a sync-phase event.
            _record_abs!(t, ev_ref[])
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
            @debug "AxisTracker pump: libevdev_next_event error" status
            break
        end
    end
    return nothing
end

@inline function _record_abs!(t::AxisTracker, ev::InputEvent)
    if ev.type == UInt16(EV_ABS)
        slot = get(t.values, ev.code, nothing)
        if slot !== nothing
            slot[] = ev.value
        end
    end
    return nothing
end

"""
    close(t::AxisTracker)

Stop the pump task and (if the tracker owns its device) close the
underlying [`EvdevDevice`](@ref). Idempotent.

After `close`, the pump task stops and the tracker no longer records
new events. The slot dictionaries are retained, so [`axis`](@ref) and
[`axis_values`](@ref) continue to return the values held at shutdown.

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
axis(t::AxisTracker, code::Integer) = t.values[UInt16(code)][]

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
    for (code, slot) in t.values
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
