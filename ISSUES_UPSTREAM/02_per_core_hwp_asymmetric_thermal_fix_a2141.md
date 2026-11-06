# Discussion / Feature: Mitigating bare-die Core 0 thermal spikes on MacBookPro16,1 via Per-Core HWP Asymmetric Turbo

## Target Hardware
* **Model:** MacBookPro16,1 (A2141)
* **Processor:** Intel Core i7-9750H

## Problem Overview
On bare-die mobile Intel chips in the 16" chassis subjected to years of thermal cycling, thermal paste pump-out or spring screw tension variances frequently lead to thermal transfer degradation predominantly on **Core 0**.
Under default Linux governors (`intel_pstate`), brief UI tasks ramp core voltages to 1.35V+ at 4.5 GHz, sending Core 0 from 65°C to 100°C within 180 ms. 
Because the Apple T2 SMC rolling filter (`TC0E`) introduces ~900 ms of latency, the CPU triggers thousands of hardware `PROCHOT` throttle events before fans can react.

Common forum advice recommends disabling Turbo Boost completely or capping all cores to a low frequency, causing substantial loss in single-threaded burst performance.

## Solution Architecture: Per-Core Asymmetric Turbo
Instead of symmetric capping, we can leverage `intel_pstate` Speed Shift (HWP) per-core sysfs interfaces:
1. Isolate and cap Core 0 (cpu0, cpu6) to 3.4 GHz with `balance_power`.
2. Allow healthy cores (Core 4 & 5 / cpu4, cpu10, cpu5, cpu11) to boost up to 4.50 GHz with `balance_performance`.
3. Set a software TCC Offset of 3°C (`cooling_device18`) so the CPU modulates frequency in microseconds at 97°C without emergency PROCHOT.

## Empirical Benchmark Results
* **PROCHOT throttle count:** Reduced from 35,292 events / 77 min down to **0 sustained events** (+62 transient micro-blips during extreme synthetic zig-zag torture).
* **Single-core burst performance:** Fully preserved at 4.50 GHz on healthy cores (Core 4 & 5).
* **All-Core Sustained Throughput:** 3.10 – 3.30 GHz sustained under 100% 12-thread load (exceeding Intel 2.60 GHz base clock).
* **Rapid Thermal Shedding:** Instantaneous drop from 100°C down to 70°C within 400 ms on load cuts.
* **Peak Core 0 temperature:** Capped below critical trip points under synthetic stress.
* **Sleep/Wake Persistence:** Includes `/lib/systemd/system-sleep/` hook to maintain tuning across suspend cycles.

Full scripts and systemd units available at:
https://github.com/mylnzon58/t2-macbook-pro-16-1-thermal-performance-fix-ubuntu
