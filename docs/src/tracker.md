# Axis tracker

```@meta
CurrentModule = Libevdev
```

[`AxisTracker`](@ref) is a thin self-contained wrapper for input
devices that report axis state — joysticks, gamepads, tablets,
touchpads, mice. A background task drains events from the underlying
device and updates atomic slots in two flavours:

- **Absolute axes (`EV_ABS`)** — slot holds the *latest reported
  value*. Use for joystick positions, touch coordinates, pen pressure.
- **Relative axes (`EV_REL`)** — slot holds the *cumulative sum of
  deltas* since construction (or last consume). Use for mouse motion,
  scroll wheel.

All queries are lock-free atomic loads.

```julia
# Joystick / gamepad: read absolute axis state at any rate
t = AxisTracker("/dev/input/event10")
@show axis_codes(t)
@show axis(t, ABS_X)
@show axis_values(t)
close(t)
```

```julia
# Mouse: accumulate deltas, consume per frame
t = AxisTracker("/dev/input/event5")
while !done
    dx = consume_rel!(t, REL_X)
    dy = consume_rel!(t, REL_Y)
    move_camera(dx, dy)
    sleep(1/60)
end
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

## Absolute-axis queries

```@docs
axis
axis_values
axis_range
axis_codes
```

## Relative-axis queries

```@docs
rel
rel_values
rel_codes
consume_rel!
consume_rel_values!
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
