#!/bin/bash
# ==============================================================================
# MacBook Pro 16,1 (A2141) Dynamic Thermal & Power Watchdog Daemon
# Author: Juan José Monzón (@mylnzon58)
#
# Hardware Topology:
# Intel Core i7-9750H (6 Cores / 12 Threads)
# - Core 0: cpu0, cpu6  (Thermally sensitive corner, protected)
# - Core 1: cpu1, cpu7  (Balanced)
# - Core 2: cpu2, cpu8  (Balanced)
# - Core 3: cpu3, cpu9  (Balanced)
# - Core 4: cpu4, cpu10 (Optimal heatsink contact, Max Boost)
# - Core 5: cpu5, cpu11 (Optimal heatsink contact, Max Boost)
# ==============================================================================

# 1. Base Hardware Initialization
init_hardware() {
    # GPU AMD Radeon Pro in auto with 3D profile
    for card in /sys/class/drm/card*/device; do
        [ -f "$card/power_dpm_force_performance_level" ] && echo auto > "$card/power_dpm_force_performance_level" 2>/dev/null || true
        [ -f "$card/pp_power_profile_mode" ] && echo 1 > "$card/pp_power_profile_mode" 2>/dev/null || true
    done

    # Cut ghost HPD polling on disconnected Intel i915 ports (>10ms lag)
    for conn in /sys/class/drm/card*-DP-*/status /sys/class/drm/card*-HDMI-*/status; do
        if [ -f "$conn" ]; then
            card_dir=$(dirname "$conn")
            driver_link=$(readlink -f "$card_dir/device/driver" 2>/dev/null || true)
            if [[ "$driver_link" == *"i915" ]]; then
                echo off > "$conn" 2>/dev/null || true
            fi
        fi
    done

    # zswap in RAM with lz4 and low swappiness
    if [ -d /sys/module/zswap/parameters ]; then
        echo lz4 > /sys/module/zswap/parameters/compressor 2>/dev/null || true
        echo 25 > /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || true
        echo Y > /sys/module/zswap/parameters/enabled 2>/dev/null || true
    fi
    sysctl -w vm.swappiness=15 >/dev/null 2>&1 || true

    # Apple T2 CDC-NCM link
    if [ -d /sys/class/net/t2_ncm ]; then
        sysctl -w net.ipv6.conf.t2_ncm.accept_dad=0 >/dev/null 2>&1 || true
        ip link set dev t2_ncm addrgenmode eui64 2>/dev/null || true
        ip link set dev t2_ncm up 2>/dev/null || true
        ip -6 addr replace fe80::aede:48ff:fe00:1122/64 dev t2_ncm nodad 2>/dev/null || \
        ip -6 addr add fe80::aede:48ff:fe00:1122/64 dev t2_ncm nodad 2>/dev/null || true
    fi
}

# 2. Profiles Definition
apply_burst_profile() {
    # Cores 4 & 5 (cpu4, cpu10, cpu5, cpu11) -> 4.50 GHz Max Turbo
    for c in cpu4 cpu10 cpu5 cpu11; do
        echo 4500000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
        echo balance_performance > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
    done

    # Cores 1 & 2 (cpu1, cpu7, cpu2, cpu8) -> 4.20 GHz High Turbo
    for c in cpu1 cpu7 cpu2 cpu8; do
        echo 4200000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
        echo balance_performance > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
    done

    # Core 3 (cpu3, cpu9) -> 3.70 GHz
    for c in cpu3 cpu9; do
        echo 3700000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
        echo balance_performance > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
    done

    # Core 0 (cpu0, cpu6) -> Protected 3.40 GHz
    for c in cpu0 cpu6; do
        echo 3400000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
        echo balance_power > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
    done
}

apply_heavy_multithread_profile() {
    # Under heavy parallel load (Gradle, multi-core compilation):
    # Lock all cores to sustained optimal turbo without thermal throttling ping-pong
    # Cores 4 & 5 -> 3.60 GHz
    for c in cpu4 cpu10 cpu5 cpu11; do
        echo 3600000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
        echo balance_performance > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
    done

    # Cores 1 & 2 -> 3.50 GHz
    for c in cpu1 cpu7 cpu2 cpu8; do
        echo 3500000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
        echo balance_performance > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
    done

    # Core 3 -> 3.40 GHz
    for c in cpu3 cpu9; do
        echo 3400000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
        echo balance_performance > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
    done

    # Core 0 -> Protected 3.10 GHz
    for c in cpu0 cpu6; do
        echo 3100000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
        echo balance_power > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
    done
}

# 3. Main Loop
init_hardware
current_profile="none"

while true; do
    # A. Enforce RAPL Limits (prevent silent reset to 100W by kernel/battery events)
    if [ -d /sys/class/powercap/intel-rapl:0 ]; then
        rapl_cur=$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || echo 0)
        if [ "$rapl_cur" -ne 45000000 ]; then
            echo 45000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || true
            echo 65000000 > /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null || true
        fi
    fi

    # B. Enforce TCC Offset = 3 (97C silicon brake instead of 100C hard crash)
    for cdev in /sys/class/thermal/cooling_device*; do
        if [ "$(cat "$cdev/type" 2>/dev/null)" = "TCC Offset" ]; then
            tcc_cur=$(cat "$cdev/cur_state" 2>/dev/null || echo 0)
            if [ "$tcc_cur" -ne 3 ]; then
                echo 3 > "$cdev/cur_state" 2>/dev/null || true
            fi
        fi
    done

    # C. Read CPU package temperature (coretemp Package 0 or x86_pkg_temp)
    pkg_temp=0
    for h in /sys/class/hwmon/hwmon*; do
        if [ "$(cat "$h/name" 2>/dev/null)" = "coretemp" ]; then
            raw=$(cat "$h/temp1_input" 2>/dev/null || echo 0)
            pkg_temp=$((raw / 1000))
            break
        fi
    done
    if [ "$pkg_temp" -eq 0 ]; then
        for z in /sys/class/thermal/thermal_zone*; do
            ztype=$(cat "$z/type" 2>/dev/null || echo "")
            if [[ "$ztype" == *"pkg"* ]]; then
                raw=$(cat "$z/temp" 2>/dev/null || echo 0)
                pkg_temp=$((raw / 1000))
                break
            fi
        done
    fi

    # D. Determine Active Load Profile
    # Immediate bootstrap if not set yet
    if [ "$current_profile" = "none" ]; then
        if [ "$pkg_temp" -gt 84 ]; then
            apply_heavy_multithread_profile
            current_profile="heavy"
        else
            apply_burst_profile
            current_profile="burst"
        fi
    elif [ "$pkg_temp" -gt 84 ]; then
        # If package temperature > 84C, engage heavy multithread profile to prevent PROCHOT ping-pong
        if [ "$current_profile" != "heavy" ]; then
            apply_heavy_multithread_profile
            current_profile="heavy"
        fi
    elif [ "$pkg_temp" -lt 74 ]; then
        # When temperature drops below 74C, restore full 4.50 GHz burst capability
        if [ "$current_profile" != "burst" ]; then
            apply_burst_profile
            current_profile="burst"
        fi
    fi

    sleep 2
done
