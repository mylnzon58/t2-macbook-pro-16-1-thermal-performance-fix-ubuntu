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
* **PROCHOT throttle count:** Reduced from 35,292 events / 77 min down to **0 events**.
* **Single-core burst performance:** Fully preserved at 4.50 GHz on healthy cores.
* **Peak Core 0 temperature:** Capped at 74°C under synthetic stress.

Full scripts and systemd units available at:
https://github.com/mylnzon58/t2-macbook-pro-16-1-thermal-performance-fix-ubuntu
