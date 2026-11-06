#!/bin/bash
# 1. Potencia alta sin descontrol: 45W sostenidos (superior a los 45W TDP de fabrica) y 65W pico
if [ -d /sys/class/powercap/intel-rapl:0 ]; then
    echo 45000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || true
    echo 65000000 > /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null || true
fi

# 2. Configuracion ASIMETRICA por nucleo fisico (Per-Core HWP Tuning):
# - Core 4 (cpu4, cpu10) y Core 5 (cpu5, cpu11): 100% libres a 4.50 GHz (4500000 kHz) - Mejor contacto termico
# - Core 1 (cpu1, cpu7)  y Core 2 (cpu2, cpu8):  Potentes a 4.20 GHz (4200000 kHz)
# - Core 3 (cpu3, cpu9):                         Equilibrado a 3.70 GHz (3700000 kHz)
# - Core 0 (cpu0, cpu6):                         Protegido a 3.40 GHz (3400000 kHz) para no disparar PROCHOT en todo el chip

# Core 4 y Core 5 -> 4.50 GHz Maximo Turbo
for c in cpu4 cpu10 cpu5 cpu11; do
    echo 4500000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
    echo balance_performance > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
done

# Core 1 y Core 2 -> 4.20 GHz Alto Turbo
for c in cpu1 cpu7 cpu2 cpu8; do
    echo 4200000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
    echo balance_performance > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
done

# Core 3 -> 3.70 GHz
for c in cpu3 cpu9; do
    echo 3700000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
    echo balance_power > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
done

# Core 0 (el nucleo con menor contacto fisico) -> 3.40 GHz
for c in cpu0 cpu6; do
    echo 3400000 > /sys/devices/system/cpu/$c/cpufreq/scaling_max_freq 2>/dev/null || true
    echo balance_power > /sys/devices/system/cpu/$c/cpufreq/energy_performance_preference 2>/dev/null || true
done

# 3. TCC Offset suave (3 grados = 97C) en el silicio para modular MHz en microsegundos sin frenazo de emergencia a 100C
for cdev in /sys/class/thermal/cooling_device*; do
    if [ "$(cat $cdev/type 2>/dev/null)" = "TCC Offset" ]; then
        echo 3 > "$cdev/cur_state" 2>/dev/null || true
    fi
done

# 4. GPU AMD Radeon Pro en 'auto' + Perfil 1 (3D_FULL_SCREEN) para respuesta instantanea en multiples pantallas
for card in /sys/class/drm/card*/device; do
    if [ -f "$card/power_dpm_force_performance_level" ]; then
        echo auto > "$card/power_dpm_force_performance_level" 2>/dev/null || true
    fi
    if [ -f "$card/pp_power_profile_mode" ]; then
        echo 1 > "$card/pp_power_profile_mode" 2>/dev/null || true
    fi
done

# 5. Cortar sondeo HPD fantasma (>10ms lag) en conectores desconectados de Intel i915
for conn in /sys/class/drm/card*-DP-*/status /sys/class/drm/card*-HDMI-*/status; do
    if [ -f "$conn" ]; then
        card_dir=$(dirname "$conn")
        driver_link=$(readlink -f "$card_dir/device/driver" 2>/dev/null || true)
        if [[ "$driver_link" == *"i915" ]]; then
            echo off > "$conn" 2>/dev/null || true
        fi
    fi
done

# 6. ZSWAP activo en RAM con compresor ultrarrapido LZ4 y swappiness bajo (15)
if [ -d /sys/module/zswap/parameters ]; then
    echo lz4 > /sys/module/zswap/parameters/compressor 2>/dev/null || true
    echo 25 > /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || true
    echo Y > /sys/module/zswap/parameters/enabled 2>/dev/null || true
fi
sysctl -w vm.swappiness=15 >/dev/null 2>&1 || true

# 7. Enlace interno Apple T2 CDC-NCM para bridgeOS / Touch ID
if [ -d /sys/class/net/t2_ncm ]; then
    ip link set dev t2_ncm addrgenmode eui64 2>/dev/null || true
    ip link set dev t2_ncm up 2>/dev/null || true
    ip -6 addr add fe80::aede:48ff:fe00:1122/64 dev t2_ncm 2>/dev/null || true
fi
