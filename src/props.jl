# Property / capability / identity accessors. All wrappers hold
# `dev.lock` for the duration of the ccall; results are converted to
# idiomatic Julia types (`String`/`nothing` for possibly-null C strings,
# `Int` for the small-int getters, `Bool` for predicates).

# Local mirror of the kernel's `struct input_absinfo`. The generated
# bindings hand back Ptr{Cvoid} for libevdev_get_abs_info, so we define
# the layout here for `unsafe_load`. Matches the kernel ABI on every
# Linux platform libevdev supports.
struct input_absinfo
    value::Int32
    minimum::Int32
    maximum::Int32
    fuzz::Int32
    flat::Int32
    resolution::Int32
end

# Convert a possibly-null Ptr to Union{String, Nothing} without an
# extra copy.
@inline function _cstring_or_nothing(p::Ptr)
    return p == C_NULL ? nothing : unsafe_string(Ptr{UInt8}(p))
end

"""
    name(dev::EvdevDevice) -> Union{String, Nothing}

Human-readable device name (e.g. `"AT Translated Set 2 keyboard"`).

# Returns
The name as a `String`, or `nothing` if the device has no name set.
"""
function name(dev::EvdevDevice)
    return lock(dev.lock) do
        _cstring_or_nothing(LibevdevRaw.libevdev_get_name(dev))
    end
end

"""
    phys(dev::EvdevDevice) -> Union{String, Nothing}

Physical (topological) location of the device, e.g.
`"usb-0000:00:14.0-1/input0"`.

# Returns
The location as a `String`, or `nothing` if unset.
"""
function phys(dev::EvdevDevice)
    return lock(dev.lock) do
        _cstring_or_nothing(LibevdevRaw.libevdev_get_phys(dev))
    end
end

"""
    uniq(dev::EvdevDevice) -> Union{String, Nothing}

Unique identifier reported by the device (often empty / `nothing`).
"""
function uniq(dev::EvdevDevice)
    return lock(dev.lock) do
        _cstring_or_nothing(LibevdevRaw.libevdev_get_uniq(dev))
    end
end

"""
    vendor_id(dev::EvdevDevice) -> Int

USB / PCI vendor ID.
"""
vendor_id(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibevdevRaw.libevdev_get_id_vendor(dev))
end

"""
    product_id(dev::EvdevDevice) -> Int

USB / PCI product ID.
"""
product_id(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibevdevRaw.libevdev_get_id_product(dev))
end

"""
    bustype(dev::EvdevDevice) -> Int

Bus type identifier. One of the kernel `BUS_*` constants from
`<linux/input.h>` (e.g. `BUS_USB = 3`, `BUS_PCI = 1`).
"""
bustype(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibevdevRaw.libevdev_get_id_bustype(dev))
end

"""
    version(dev::EvdevDevice) -> Int

Device firmware/protocol version reported by the driver.
"""
version(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibevdevRaw.libevdev_get_id_version(dev))
end

"""
    driver_version(dev::EvdevDevice) -> Int

Input subsystem protocol version (`EVIOCGVERSION`).
"""
driver_version(dev::EvdevDevice) = lock(dev.lock) do
    Int(LibevdevRaw.libevdev_get_driver_version(dev))
end

"""
    has_event(dev::EvdevDevice, type::Integer, code::Integer=-1) -> Bool

Query whether the device advertises the given event class.

# Arguments
- `type`: event type code (`EV_KEY`, `EV_ABS`, ...).
- `code`: type-specific code. When `code < 0` (default), queries whether
  the device emits *any* event of `type`; otherwise queries the specific
  `(type, code)` pair.

# Returns
`true` if the capability is advertised, `false` otherwise.
"""
function has_event(dev::EvdevDevice, type::Integer, code::Integer=-1)
    return lock(dev.lock) do
        if code < 0
            LibevdevRaw.libevdev_has_event_type(dev, Cuint(type)) != 0
        else
            LibevdevRaw.libevdev_has_event_code(dev, Cuint(type), Cuint(code)) != 0
        end
    end
end

"""
    has_property(dev::EvdevDevice, prop::Integer) -> Bool

Query whether the device has the given input property (`INPUT_PROP_*`
from `<linux/input-event-codes.h>`).
"""
function has_property(dev::EvdevDevice, prop::Integer)
    return lock(dev.lock) do
        LibevdevRaw.libevdev_has_property(dev, Cuint(prop)) != 0
    end
end

"""
    grab(dev::EvdevDevice)

Acquire exclusive access to the device (`EVIOCGRAB`). While grabbed,
this process is the sole receiver of events from the device.

# Throws
- `EvdevError` if another process already holds an exclusive grab.
"""
function grab(dev::EvdevDevice)
    lock(dev.lock) do
        check(LibevdevRaw.libevdev_grab(dev, LibevdevRaw.LIBEVDEV_GRAB), "libevdev_grab")
    end
    return nothing
end

"""
    ungrab(dev::EvdevDevice)

Release a prior [`grab`](@ref).
"""
function ungrab(dev::EvdevDevice)
    lock(dev.lock) do
        check(LibevdevRaw.libevdev_grab(dev, LibevdevRaw.LIBEVDEV_UNGRAB),
              "libevdev_grab(UNGRAB)")
    end
    return nothing
end

"""
    abs_info(dev::EvdevDevice, code::Integer) -> NamedTuple

Return the `EV_ABS` axis description for `code`.

# Returns
A `NamedTuple` with fields `minimum`, `maximum`, `fuzz`, `flat`,
`resolution` (all `Int`), as reported by the kernel `EVIOCGABS` ioctl.

# Throws
- `EvdevError` (with `errno = ENOENT`) if the device doesn't expose
  that axis (libevdev returns NULL).
"""
function abs_info(dev::EvdevDevice, code::Integer)
    return lock(dev.lock) do
        p = LibevdevRaw.libevdev_get_abs_info(dev, Cuint(code))
        if p == C_NULL
            throw(EvdevError(Int32(Libc.ENOENT), "libevdev_get_abs_info(code=$code)"))
        end
        info = unsafe_load(Ptr{input_absinfo}(p))
        (minimum=Int(info.minimum),
         maximum=Int(info.maximum),
         fuzz=Int(info.fuzz),
         flat=Int(info.flat),
         resolution=Int(info.resolution))
    end
end

# -----------------------------------------------------------------------
# Setters / capability builders for synthetic devices.
#
# These are most useful in combination with the no-fd `EvdevDevice()`
# constructor: build a blank handle, configure its identity and
# capabilities, then pass it as a template to `UinputDevice` to
# materialize a virtual input device. They also work on real devices
# (libevdev mutates its in-memory state without touching the kernel),
# but that's rarely what you want.
# -----------------------------------------------------------------------

"""
    set_name!(dev::EvdevDevice, name::AbstractString)

Set the device name (the string returned by [`name`](@ref)).
"""
function set_name!(dev::EvdevDevice, name::AbstractString)
    lock(dev.lock) do
        LibevdevRaw.libevdev_set_name(dev, name)
    end
    return nothing
end

"""
    set_phys!(dev::EvdevDevice, phys::AbstractString)

Set the device's physical-location string.
"""
function set_phys!(dev::EvdevDevice, phys::AbstractString)
    lock(dev.lock) do
        LibevdevRaw.libevdev_set_phys(dev, phys)
    end
    return nothing
end

"""
    set_uniq!(dev::EvdevDevice, uniq::AbstractString)

Set the device's unique-identifier string.
"""
function set_uniq!(dev::EvdevDevice, uniq::AbstractString)
    lock(dev.lock) do
        LibevdevRaw.libevdev_set_uniq(dev, uniq)
    end
    return nothing
end

"""
    set_vendor_id!(dev::EvdevDevice, vendor::Integer)

Set the device's USB / PCI vendor ID.
"""
function set_vendor_id!(dev::EvdevDevice, vendor::Integer)
    lock(dev.lock) do
        LibevdevRaw.libevdev_set_id_vendor(dev, Cint(vendor))
    end
    return nothing
end

"""
    set_product_id!(dev::EvdevDevice, product::Integer)

Set the device's USB / PCI product ID.
"""
function set_product_id!(dev::EvdevDevice, product::Integer)
    lock(dev.lock) do
        LibevdevRaw.libevdev_set_id_product(dev, Cint(product))
    end
    return nothing
end

"""
    set_bustype!(dev::EvdevDevice, bustype::Integer)

Set the device's bus type — one of the `BUS_*` constants.
"""
function set_bustype!(dev::EvdevDevice, bustype::Integer)
    lock(dev.lock) do
        LibevdevRaw.libevdev_set_id_bustype(dev, Cint(bustype))
    end
    return nothing
end

"""
    set_version!(dev::EvdevDevice, version::Integer)

Set the device's firmware/protocol version identifier.
"""
function set_version!(dev::EvdevDevice, version::Integer)
    lock(dev.lock) do
        LibevdevRaw.libevdev_set_id_version(dev, Cint(version))
    end
    return nothing
end

"""
    enable_event!(dev::EvdevDevice, type::Integer, code::Integer=-1;
                   minimum=nothing, maximum=nothing,
                   fuzz=0, flat=0, resolution=0)

Advertise that `dev` emits the given event class. With `code < 0`
(default), enables the entire event `type` (`EV_KEY`, `EV_ABS`, ...).
Otherwise enables the specific `(type, code)` pair (`KEY_A`, `ABS_X`, ...).

For `EV_ABS` codes, also supply the axis range via the `minimum` /
`maximum` keyword arguments (libevdev requires the axis description
to be attached at enable-time, not in a follow-up call). Optional
`fuzz`, `flat`, and `resolution` kwargs default to `0`. For other
event types, leave the kwargs at their defaults.

# Throws
- `EvdevError` if libevdev rejects the call (e.g. `EV_ABS` enable
  without `minimum`/`maximum`).
"""
function enable_event!(dev::EvdevDevice, type::Integer, code::Integer=-1;
                        minimum::Union{Integer,Nothing}=nothing,
                        maximum::Union{Integer,Nothing}=nothing,
                        fuzz::Integer=0, flat::Integer=0,
                        resolution::Integer=0)
    lock(dev.lock) do
        if code < 0
            check(LibevdevRaw.libevdev_enable_event_type(dev, Cuint(type)),
                  "libevdev_enable_event_type")
        elseif minimum !== nothing && maximum !== nothing
            info = input_absinfo(Int32(0), Int32(minimum), Int32(maximum),
                                  Int32(fuzz), Int32(flat), Int32(resolution))
            ref = Ref(info)
            GC.@preserve ref begin
                check(LibevdevRaw.libevdev_enable_event_code(dev, Cuint(type),
                            Cuint(code),
                            Base.unsafe_convert(Ptr{input_absinfo}, ref)),
                      "libevdev_enable_event_code")
            end
        else
            check(LibevdevRaw.libevdev_enable_event_code(dev, Cuint(type),
                                                      Cuint(code), C_NULL),
                  "libevdev_enable_event_code")
        end
    end
    return nothing
end

"""
    disable_event!(dev::EvdevDevice, type::Integer, code::Integer=-1)

Remove the given event class from the device's advertised capabilities.
Mirror of [`enable_event!`](@ref).
"""
function disable_event!(dev::EvdevDevice, type::Integer, code::Integer=-1)
    lock(dev.lock) do
        if code < 0
            check(LibevdevRaw.libevdev_disable_event_type(dev, Cuint(type)),
                  "libevdev_disable_event_type")
        else
            check(LibevdevRaw.libevdev_disable_event_code(dev, Cuint(type),
                                                       Cuint(code)),
                  "libevdev_disable_event_code")
        end
    end
    return nothing
end

"""
    enable_property!(dev::EvdevDevice, prop::Integer)

Set one of the `INPUT_PROP_*` capability flags on `dev`.

# Throws
- `EvdevError` if libevdev rejects the call.
"""
function enable_property!(dev::EvdevDevice, prop::Integer)
    lock(dev.lock) do
        check(LibevdevRaw.libevdev_enable_property(dev, Cuint(prop)),
              "libevdev_enable_property")
    end
    return nothing
end

"""
    disable_property!(dev::EvdevDevice, prop::Integer)

Unset one of the `INPUT_PROP_*` capability flags on `dev`.

# Throws
- `EvdevError` if libevdev rejects the call.
"""
function disable_property!(dev::EvdevDevice, prop::Integer)
    lock(dev.lock) do
        check(LibevdevRaw.libevdev_disable_property(dev, Cuint(prop)),
              "libevdev_disable_property")
    end
    return nothing
end

"""
    set_abs_info!(dev::EvdevDevice, code::Integer;
                   minimum, maximum, fuzz=0, flat=0, resolution=0)

Update the axis description for an `EV_ABS` code that's already
enabled on `dev`. For the *initial* enable + info bundle (the usual
case when building a synthetic device), pass the same kwargs to
[`enable_event!`](@ref) instead; this function is for changing the
range of an axis that was enabled earlier.

# Arguments
- `code`: an `ABS_*` constant.
- `minimum`, `maximum`: the axis range (required).
- `fuzz`: noise threshold; the driver filters out smaller changes
  before they reach userspace. Default `0`.
- `flat`: dead-zone size around the resting position. Default `0`.
- `resolution`: units per millimeter (spatial) or per radian
  (rotational); `0` if unknown. Default `0`.
"""
function set_abs_info!(dev::EvdevDevice, code::Integer;
                        minimum::Integer, maximum::Integer,
                        fuzz::Integer=0, flat::Integer=0,
                        resolution::Integer=0)
    info = input_absinfo(Int32(0), Int32(minimum), Int32(maximum),
                          Int32(fuzz), Int32(flat), Int32(resolution))
    ref = Ref(info)
    lock(dev.lock) do
        GC.@preserve ref begin
            LibevdevRaw.libevdev_set_abs_info(dev, Cuint(code),
                                            Base.unsafe_convert(Ptr{input_absinfo}, ref))
        end
    end
    return nothing
end
