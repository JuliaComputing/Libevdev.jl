# Devices

```@meta
CurrentModule = Libev
```

The [`EvdevDevice`](@ref) type is the central handle: it owns a libevdev
context plus an open file descriptor to a `/dev/input/eventN` node, and
guards them with a per-device lock so the same device can be safely
shared across tasks.

## Lifecycle

```@docs
EvdevDevice
EvdevDevice()
EvdevDevice(::AbstractString)
EvdevDevice(::Base.RawFD)
Base.open(::Type{EvdevDevice}, ::AbstractString)
Base.close(::EvdevDevice)
Base.isopen(::EvdevDevice)
```

## Identity

```@docs
name
phys
uniq
vendor_id
product_id
bustype
version
driver_version
```

## Capabilities

```@docs
has_event
has_property
abs_info
```

## Building synthetic devices

For uinput workflows that materialize a virtual device from scratch
(rather than cloning an existing one), build a blank
[`EvdevDevice()`](@ref), configure it with the setters below, then
hand it to [`UinputDevice`](@ref).

```@docs
set_name!
set_phys!
set_uniq!
set_vendor_id!
set_product_id!
set_bustype!
set_version!
enable_event!
disable_event!
enable_property!
disable_property!
set_abs_info!
```

## Exclusive access

```@docs
grab
ungrab
```

## Errors

```@docs
EvdevError
```
