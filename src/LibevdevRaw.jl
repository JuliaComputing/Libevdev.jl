module LibevdevRaw

using libevdev_jll
export libevdev_jll

using CEnum: CEnum, @cenum

mutable struct libevdev_uinput end

@cenum libevdev_uinput_open_mode::Int32 begin
    LIBEVDEV_UINPUT_OPEN_MANAGED = -2
end

mutable struct libevdev end

function libevdev_uinput_create_from_device(dev, uinput_fd, uinput_dev)
    ccall((:libevdev_uinput_create_from_device, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cint, Ptr{Ptr{libevdev_uinput}}), dev, uinput_fd, uinput_dev)
end

function libevdev_uinput_destroy(uinput_dev)
    ccall((:libevdev_uinput_destroy, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev_uinput},), uinput_dev)
end

function libevdev_uinput_get_fd(uinput_dev)
    ccall((:libevdev_uinput_get_fd, libevdev_jll.libevdev), Cint, (Ptr{libevdev_uinput},), uinput_dev)
end

function libevdev_uinput_get_syspath(uinput_dev)
    ccall((:libevdev_uinput_get_syspath, libevdev_jll.libevdev), Ptr{Cchar}, (Ptr{libevdev_uinput},), uinput_dev)
end

function libevdev_uinput_get_devnode(uinput_dev)
    ccall((:libevdev_uinput_get_devnode, libevdev_jll.libevdev), Ptr{Cchar}, (Ptr{libevdev_uinput},), uinput_dev)
end

function libevdev_uinput_write_event(uinput_dev, type, code, value)
    ccall((:libevdev_uinput_write_event, libevdev_jll.libevdev), Cint, (Ptr{libevdev_uinput}, Cuint, Cuint, Cint), uinput_dev, type, code, value)
end

@cenum libevdev_read_flag::UInt32 begin
    LIBEVDEV_READ_FLAG_SYNC = 1
    LIBEVDEV_READ_FLAG_NORMAL = 2
    LIBEVDEV_READ_FLAG_FORCE_SYNC = 4
    LIBEVDEV_READ_FLAG_BLOCKING = 8
end

function libevdev_new()
    ccall((:libevdev_new, libevdev_jll.libevdev), Ptr{libevdev}, ())
end

function libevdev_new_from_fd(fd, dev)
    ccall((:libevdev_new_from_fd, libevdev_jll.libevdev), Cint, (Cint, Ptr{Ptr{libevdev}}), fd, dev)
end

function libevdev_free(dev)
    ccall((:libevdev_free, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev},), dev)
end

@cenum libevdev_log_priority::UInt32 begin
    LIBEVDEV_LOG_ERROR = 10
    LIBEVDEV_LOG_INFO = 20
    LIBEVDEV_LOG_DEBUG = 30
end

# typedef void ( * libevdev_log_func_t ) ( enum libevdev_log_priority priority , void * data , const char * file , int line , const char * func , const char * format , va_list args )
const libevdev_log_func_t = Ptr{Cvoid}

function libevdev_set_log_function(logfunc, data)
    ccall((:libevdev_set_log_function, libevdev_jll.libevdev), Cvoid, (libevdev_log_func_t, Ptr{Cvoid}), logfunc, data)
end

function libevdev_set_log_priority(priority)
    ccall((:libevdev_set_log_priority, libevdev_jll.libevdev), Cvoid, (libevdev_log_priority,), priority)
end

function libevdev_get_log_priority()
    ccall((:libevdev_get_log_priority, libevdev_jll.libevdev), libevdev_log_priority, ())
end

# typedef void ( * libevdev_device_log_func_t ) ( const struct libevdev * dev , enum libevdev_log_priority priority , void * data , const char * file , int line , const char * func , const char * format , va_list args )
const libevdev_device_log_func_t = Ptr{Cvoid}

function libevdev_set_device_log_function(dev, logfunc, priority, data)
    ccall((:libevdev_set_device_log_function, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, libevdev_device_log_func_t, libevdev_log_priority, Ptr{Cvoid}), dev, logfunc, priority, data)
end

@cenum libevdev_grab_mode::UInt32 begin
    LIBEVDEV_GRAB = 3
    LIBEVDEV_UNGRAB = 4
end

function libevdev_grab(dev, grab)
    ccall((:libevdev_grab, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, libevdev_grab_mode), dev, grab)
end

function libevdev_set_fd(dev, fd)
    ccall((:libevdev_set_fd, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cint), dev, fd)
end

function libevdev_change_fd(dev, fd)
    ccall((:libevdev_change_fd, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cint), dev, fd)
end

function libevdev_get_fd(dev)
    ccall((:libevdev_get_fd, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

@cenum libevdev_read_status::UInt32 begin
    LIBEVDEV_READ_STATUS_SUCCESS = 0
    LIBEVDEV_READ_STATUS_SYNC = 1
end

function libevdev_next_event(dev, flags, ev)
    ccall((:libevdev_next_event, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Ptr{Cvoid}), dev, flags, ev)
end

function libevdev_has_event_pending(dev)
    ccall((:libevdev_has_event_pending, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

function libevdev_get_name(dev)
    ccall((:libevdev_get_name, libevdev_jll.libevdev), Ptr{Cchar}, (Ptr{libevdev},), dev)
end

function libevdev_set_name(dev, name)
    ccall((:libevdev_set_name, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Ptr{Cchar}), dev, name)
end

function libevdev_get_phys(dev)
    ccall((:libevdev_get_phys, libevdev_jll.libevdev), Ptr{Cchar}, (Ptr{libevdev},), dev)
end

function libevdev_set_phys(dev, phys)
    ccall((:libevdev_set_phys, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Ptr{Cchar}), dev, phys)
end

function libevdev_get_uniq(dev)
    ccall((:libevdev_get_uniq, libevdev_jll.libevdev), Ptr{Cchar}, (Ptr{libevdev},), dev)
end

function libevdev_set_uniq(dev, uniq)
    ccall((:libevdev_set_uniq, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Ptr{Cchar}), dev, uniq)
end

function libevdev_get_id_product(dev)
    ccall((:libevdev_get_id_product, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

function libevdev_set_id_product(dev, product_id)
    ccall((:libevdev_set_id_product, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cint), dev, product_id)
end

function libevdev_get_id_vendor(dev)
    ccall((:libevdev_get_id_vendor, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

function libevdev_set_id_vendor(dev, vendor_id)
    ccall((:libevdev_set_id_vendor, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cint), dev, vendor_id)
end

function libevdev_get_id_bustype(dev)
    ccall((:libevdev_get_id_bustype, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

function libevdev_set_id_bustype(dev, bustype)
    ccall((:libevdev_set_id_bustype, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cint), dev, bustype)
end

function libevdev_get_id_version(dev)
    ccall((:libevdev_get_id_version, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

function libevdev_set_id_version(dev, version)
    ccall((:libevdev_set_id_version, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cint), dev, version)
end

function libevdev_get_driver_version(dev)
    ccall((:libevdev_get_driver_version, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

function libevdev_has_property(dev, prop)
    ccall((:libevdev_has_property, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, prop)
end

function libevdev_enable_property(dev, prop)
    ccall((:libevdev_enable_property, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, prop)
end

function libevdev_disable_property(dev, prop)
    ccall((:libevdev_disable_property, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, prop)
end

function libevdev_has_event_type(dev, type)
    ccall((:libevdev_has_event_type, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, type)
end

function libevdev_has_event_code(dev, type, code)
    ccall((:libevdev_has_event_code, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint), dev, type, code)
end

function libevdev_get_abs_minimum(dev, code)
    ccall((:libevdev_get_abs_minimum, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, code)
end

function libevdev_get_abs_maximum(dev, code)
    ccall((:libevdev_get_abs_maximum, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, code)
end

function libevdev_get_abs_fuzz(dev, code)
    ccall((:libevdev_get_abs_fuzz, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, code)
end

function libevdev_get_abs_flat(dev, code)
    ccall((:libevdev_get_abs_flat, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, code)
end

function libevdev_get_abs_resolution(dev, code)
    ccall((:libevdev_get_abs_resolution, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, code)
end

function libevdev_get_abs_info(dev, code)
    ccall((:libevdev_get_abs_info, libevdev_jll.libevdev), Ptr{Cvoid}, (Ptr{libevdev}, Cuint), dev, code)
end

function libevdev_get_event_value(dev, type, code)
    ccall((:libevdev_get_event_value, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint), dev, type, code)
end

function libevdev_set_event_value(dev, type, code, value)
    ccall((:libevdev_set_event_value, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint, Cint), dev, type, code, value)
end

function libevdev_fetch_event_value(dev, type, code, value)
    ccall((:libevdev_fetch_event_value, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint, Ptr{Cint}), dev, type, code, value)
end

function libevdev_get_slot_value(dev, slot, code)
    ccall((:libevdev_get_slot_value, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint), dev, slot, code)
end

function libevdev_set_slot_value(dev, slot, code, value)
    ccall((:libevdev_set_slot_value, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint, Cint), dev, slot, code, value)
end

function libevdev_fetch_slot_value(dev, slot, code, value)
    ccall((:libevdev_fetch_slot_value, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint, Ptr{Cint}), dev, slot, code, value)
end

function libevdev_get_num_slots(dev)
    ccall((:libevdev_get_num_slots, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

function libevdev_get_current_slot(dev)
    ccall((:libevdev_get_current_slot, libevdev_jll.libevdev), Cint, (Ptr{libevdev},), dev)
end

function libevdev_set_abs_minimum(dev, code, val)
    ccall((:libevdev_set_abs_minimum, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cuint, Cint), dev, code, val)
end

function libevdev_set_abs_maximum(dev, code, val)
    ccall((:libevdev_set_abs_maximum, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cuint, Cint), dev, code, val)
end

function libevdev_set_abs_fuzz(dev, code, val)
    ccall((:libevdev_set_abs_fuzz, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cuint, Cint), dev, code, val)
end

function libevdev_set_abs_flat(dev, code, val)
    ccall((:libevdev_set_abs_flat, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cuint, Cint), dev, code, val)
end

function libevdev_set_abs_resolution(dev, code, val)
    ccall((:libevdev_set_abs_resolution, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cuint, Cint), dev, code, val)
end

function libevdev_set_abs_info(dev, code, abs)
    ccall((:libevdev_set_abs_info, libevdev_jll.libevdev), Cvoid, (Ptr{libevdev}, Cuint, Ptr{Cvoid}), dev, code, abs)
end

function libevdev_enable_event_type(dev, type)
    ccall((:libevdev_enable_event_type, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, type)
end

function libevdev_disable_event_type(dev, type)
    ccall((:libevdev_disable_event_type, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint), dev, type)
end

function libevdev_enable_event_code(dev, type, code, data)
    ccall((:libevdev_enable_event_code, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint, Ptr{Cvoid}), dev, type, code, data)
end

function libevdev_disable_event_code(dev, type, code)
    ccall((:libevdev_disable_event_code, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Cuint), dev, type, code)
end

function libevdev_kernel_set_abs_info(dev, code, abs)
    ccall((:libevdev_kernel_set_abs_info, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, Ptr{Cvoid}), dev, code, abs)
end

@cenum libevdev_led_value::UInt32 begin
    LIBEVDEV_LED_ON = 3
    LIBEVDEV_LED_OFF = 4
end

function libevdev_kernel_set_led_value(dev, code, value)
    ccall((:libevdev_kernel_set_led_value, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cuint, libevdev_led_value), dev, code, value)
end

function libevdev_set_clock_id(dev, clockid)
    ccall((:libevdev_set_clock_id, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Cint), dev, clockid)
end

function libevdev_event_is_type(ev, type)
    ccall((:libevdev_event_is_type, libevdev_jll.libevdev), Cint, (Ptr{Cvoid}, Cuint), ev, type)
end

function libevdev_event_is_code(ev, type, code)
    ccall((:libevdev_event_is_code, libevdev_jll.libevdev), Cint, (Ptr{Cvoid}, Cuint, Cuint), ev, type, code)
end

function libevdev_event_type_get_name(type)
    ccall((:libevdev_event_type_get_name, libevdev_jll.libevdev), Ptr{Cchar}, (Cuint,), type)
end

function libevdev_event_code_get_name(type, code)
    ccall((:libevdev_event_code_get_name, libevdev_jll.libevdev), Ptr{Cchar}, (Cuint, Cuint), type, code)
end

function libevdev_event_value_get_name(type, code, value)
    ccall((:libevdev_event_value_get_name, libevdev_jll.libevdev), Ptr{Cchar}, (Cuint, Cuint, Cint), type, code, value)
end

function libevdev_property_get_name(prop)
    ccall((:libevdev_property_get_name, libevdev_jll.libevdev), Ptr{Cchar}, (Cuint,), prop)
end

function libevdev_event_type_get_max(type)
    ccall((:libevdev_event_type_get_max, libevdev_jll.libevdev), Cint, (Cuint,), type)
end

function libevdev_event_type_from_name(name)
    ccall((:libevdev_event_type_from_name, libevdev_jll.libevdev), Cint, (Ptr{Cchar},), name)
end

function libevdev_event_type_from_name_n(name, len)
    ccall((:libevdev_event_type_from_name_n, libevdev_jll.libevdev), Cint, (Ptr{Cchar}, Csize_t), name, len)
end

function libevdev_event_code_from_name(type, name)
    ccall((:libevdev_event_code_from_name, libevdev_jll.libevdev), Cint, (Cuint, Ptr{Cchar}), type, name)
end

function libevdev_event_code_from_name_n(type, name, len)
    ccall((:libevdev_event_code_from_name_n, libevdev_jll.libevdev), Cint, (Cuint, Ptr{Cchar}, Csize_t), type, name, len)
end

function libevdev_event_value_from_name(type, code, name)
    ccall((:libevdev_event_value_from_name, libevdev_jll.libevdev), Cint, (Cuint, Cuint, Ptr{Cchar}), type, code, name)
end

function libevdev_event_type_from_code_name(name)
    ccall((:libevdev_event_type_from_code_name, libevdev_jll.libevdev), Cint, (Ptr{Cchar},), name)
end

function libevdev_event_type_from_code_name_n(name, len)
    ccall((:libevdev_event_type_from_code_name_n, libevdev_jll.libevdev), Cint, (Ptr{Cchar}, Csize_t), name, len)
end

function libevdev_event_code_from_code_name(name)
    ccall((:libevdev_event_code_from_code_name, libevdev_jll.libevdev), Cint, (Ptr{Cchar},), name)
end

function libevdev_event_code_from_code_name_n(name, len)
    ccall((:libevdev_event_code_from_code_name_n, libevdev_jll.libevdev), Cint, (Ptr{Cchar}, Csize_t), name, len)
end

function libevdev_event_value_from_name_n(type, code, name, len)
    ccall((:libevdev_event_value_from_name_n, libevdev_jll.libevdev), Cint, (Cuint, Cuint, Ptr{Cchar}, Csize_t), type, code, name, len)
end

function libevdev_property_from_name(name)
    ccall((:libevdev_property_from_name, libevdev_jll.libevdev), Cint, (Ptr{Cchar},), name)
end

function libevdev_property_from_name_n(name, len)
    ccall((:libevdev_property_from_name_n, libevdev_jll.libevdev), Cint, (Ptr{Cchar}, Csize_t), name, len)
end

function libevdev_get_repeat(dev, delay, period)
    ccall((:libevdev_get_repeat, libevdev_jll.libevdev), Cint, (Ptr{libevdev}, Ptr{Cint}, Ptr{Cint}), dev, delay, period)
end

# Skipping MacroDefinition: LIBEVDEV_DEPRECATED __attribute__ ( ( deprecated ) )

# exports
const PREFIXES = ["libevdev_", "LIBEVDEV_"]
for name in names(@__MODULE__; all=true), prefix in PREFIXES
    if startswith(string(name), prefix)
        @eval export $name
    end
end

end # module
