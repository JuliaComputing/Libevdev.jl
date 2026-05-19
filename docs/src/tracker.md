# Absolute-axis tracker

```@meta
CurrentModule = Libev
```

[`AxisTracker`](@ref) is a thin self-contained wrapper specialized for
joysticks, gamepads, tablets, and similar absolute-axis devices,
designed for high-rate polling. A background task drains events from
the underlying device and writes the latest value of each `EV_ABS`
axis into an atomic slot; [`axis`](@ref) / [`axis_values`](@ref)
queries read those slots with lock-free atomic loads.

```julia
t = AxisTracker("/dev/input/event10")
@show axis_codes(t)
@show axis(t, ABS_X)
@show axis_values(t)
close(t)
```

## Type

```@docs
AxisTracker
AxisRange
```

## Construction

```@docs
AxisTracker(::EvdevDevice)
AxisTracker(::AbstractString)
```

## Queries

```@docs
axis
axis_values
axis_range
axis_codes
```

## Lifecycle

```@docs
Base.close(::AxisTracker)
Base.isopen(::AxisTracker)
```

## Notes on multi-touch

The tracker stores one value per `ABS_*` code, so multi-touch (`MT_*`)
events overwrite a single slot regardless of which touch they came
from — the latest event of any code wins. For per-touch state, drive
libevdev's slot API on the underlying [`EvdevDevice`](@ref) directly.
