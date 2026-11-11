# MacBook Pro 16,1 (2019, A2141) Architectural Diagnostics & Kernel-Level Optimization Report

> **Target Hardware:** Apple MacBook Pro 16,1 (16-inch, Late 2019, Model A2141)  
> **Processor:** Intel Core i7-9750H (6 Cores / 12 Threads, Coffee Lake Refresh, 14nm)  
> **Graphics:** Dual GPU — Intel UHD Graphics 630 (iGPU) + AMD Radeon Pro 5300M 4GB GDDR6 (dGPU)  
> **Security & System Controller:** Apple T2 Security Chip (macsmc, BridgeOS)  
> **Operating System:** Ubuntu 24.04 LTS (Noble Numbat) with `linux-t2` kernel (`7.3.0-4-t2-noble`)  
> **Lead Diagnostics & Development:** Juan Monzón ([@mylnzon58](https://github.com/mylnzon58))  

---

## 1. Executive Summary & Root-Cause Failure Analysis

Prior to this intervention, the MacBook Pro 16,1 suffered from chronic system freezes, unresponsive UI behavior, and extreme thermal spikes. Minimal desktop actions (opening a browser tab, typing into a search field) caused immediate package temperatures to violently jump from **65°C to 100°C within 180 milliseconds**, triggering hardware thermal throttling (`PROCHOT`) thousands of times per hour despite both cooling fans spinning at their maximum mechanical limits (~5,300 RPM).

Through live kernel tracing (`journalctl`, `dmesg`), hardware monitor registers (`hwmon`, `coretemp`, `macsmc`), and low-level stress testing, we identified **eight distinct, compounding failures** across hardware, firmware, and operating system subsystems.

---

## 2. Detailed Technical Breakdown of Detected Problems

### Problem 1: Physical Mounting & Thermal Interface Asymmetry (`Core 0` Degradation)
* **Symptom:** Core 0 immediately hits 100°C under loads as low as 16–22W, while Core 4 and Core 5 remain at 78°C (a massive **21°C delta across a single silicon die**).
* **Hardware Root Cause:** 
  * The Intel Core i7-9750H is a **bare-die** package (no Integrated Heat Spreader / metal lid). The shared copper heatsink is a single rigid structure spanning the CPU, AMD dGPU, and VRAM chips.
  * Conventional low-to-medium viscosity thermal pastes suffer from the **"pump-out" effect** on bare-die mobile processors subjected to 90°C+ thermal expansion cycles, migrating out from the center and corners within days.
  * In this machine, thermal contact was severely compromised over the physical corner occupied by Core 0 (due to either pump-out voiding or slight mechanical tension asymmetry in the spring-loaded heatsink screws).
* **Empirical Telemetry Proof:**
  * In just **1 hour and 17 minutes of uptime**, the CPU recorded **35,292 package throttling events**.
  * Core 0 triggered **13,600 throttle events** (`82,811 ms`), whereas Core 4 triggered only **1,557 events** (`8,414 ms`) — Core 0 was throttling **nearly 10 times more frequently** than Core 4.

### Problem 2: Apple T2 SMC Telemetry Low-Pass Filter Delay (~900 ms Lag)
* **Symptom:** Cooling fans and system thermal management react too late to rapid workload spikes.
* **Firmware Root Cause:**
  * Intel core temperatures can spike to 100°C within **150–180 ms** upon turbo activation.
  * The Apple T2 Security Chip samples analog/PECI thermals and applies a rolling low-pass filter (`TC0E Filtered` / `TC0F Adjusted`) designed for acoustic smoothing, introducing an inherent **~900 ms latency**.
  * By the time the T2 chip observes the elevated temperature, the CPU has already bounced off the 100°C hard thermal ceiling dozens of times and throttled clock speeds to survival levels.

### Problem 3: Firmware RAPL Over-Allocation (100W/125W on an 82W Chassis)
* **Symptom:** The CPU draws catastrophic power bursts that immediately saturate the cooling assembly.
* **Firmware Root Cause:**
  * Apple firmware exposes Running Average Power Limit (RAPL) defaults of **100W sustained (`PL1` / `constraint_0`)** and **125W burst (`PL2` / `constraint_1`)**.
  * However, the Apple SMC hardware monitor reports a maximum chassis heatpipe target capacity (`PZ0E`) of only **82.00W total combined**.
  * When Linux `intel_pstate` allows the processor to boost aggressively, it attempts to pull over 90W on an already warm copper heatpipe, causing instantaneous thermal runaway.

### Problem 4: AMD Radeon Pro dGPU Locked to `low` Performance Mode (95 MHz VRAM)
* **Symptom:** Severe desktop stuttering, window dragging lag, and dropped frames with dual displays connected (`eDP-1` internal display + external DisplayPort `DP-6`).
* **Configuration Root Cause:**
  * A legacy udev rule forced `power_dpm_force_performance_level="low"`.
  * This locked the AMD Radeon Pro 5300M memory clock (`mclk`) strictly to **95 MHz** (down from its 750 MHz rated clock) and the GPU core (`sclk`) to **300 MHz**.
  * While intended to reduce power draw, driving two high-resolution displays (3072x1920 Retina + 1920x1080) at 95 MHz memory bandwidth starved the display engine, causing compositor frame drops while still dissipating 18W idle.

### Problem 5: Intel i915 DRM Polling Overhead on Inactive Ports
* **Symptom:** Periodic micro-stutters and kernel log warnings: `workqueue: output_poll_execute hogged CPU >10000us 131 times`.
* **Kernel Root Cause:**
  * The `i915` driver regularly polled disconnected DisplayPort and HDMI lanes on the integrated GPU, stalling the kernel workqueue for over 10 milliseconds per cycle.

### Problem 6: Apple T2 NVMe Controller I/O Latency Under Swap Pressure
* **Symptom:** Complete system freezes lasting 2 to 5 seconds when physical memory usage reached 85%+.
* **Storage Root Cause:**
  * The Apple T2 controller manages NVMe storage through a proprietary single-queue bridge.
  * Standard disk swapping (`/swapfile`) with default kernel swappiness (`vm.swappiness=60`) created synchronous I/O queues that blocked memory allocation during heavy compilation, causing **17.3 million I/O wait cycles**.

### Problem 7: Silent RAPL Reset by Kernel and Power Profiles
* **Symptom:** One-shot boot tuning scripts were overridden back to 100W PL1 after suspend or power profile changes.
* **Kernel Root Cause:**
  * Changes in battery/AC power state, GNOME `power-profiles-daemon`, or kernel suspend/resume events routinely overwrite `/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw` back to the firmware default of 100W.

### Problem 8: Thread Migration Ping-Pong and Core Utilization Drops
* **Symptom:** Under multi-core loads, cores would spike to 100% and then abruptly drop to 0%, while threads jumped erratically between cores.
* **Scheduler Root Cause:**
  * High-clock cores touched 97°C and suffered hardware PROCHOT throttling.
  * The Linux EEVDF scheduler saw their capacity collapse and migrated threads to cooler cores, which then heated up and throttled in turn, causing continuous thrashing and cache invalidation.

---

## 3. The Multi-Tier Architecture & Dynamic Watchdog Daemon

To eliminate these bottlenecks permanently, we deployed a dynamic closed-loop architecture:

### 1. Active Thermal Watchdog Daemon (`macbook-a2141-tuning-daemon.sh`)
* Runs continuously as a lightweight systemd service with a 2-second polling cycle (`0.00%` CPU overhead).
* **Continuous RAPL Enforcement:** Actively clamps `constraint_0_power_limit_uw` to **45.00W** (PL1 sustained) and `constraint_1_power_limit_uw` to **65.00W** (PL2 burst). If AC disconnects, connects, or the kernel resets RAPL, the daemon re-clamps it within 2 seconds.
* **Continuous TCC Offset Enforcement:** Enforces `TCC Offset = 3` in sysfs thermal cooling devices, maintaining a hardware ceiling of 97°C.

### 2. Thermal Hysteresis Dynamic Dual-Profile
* **Burst Profile (< 74°C Package Temperature):**
  * Cores 4 & 5 (`cpu4, cpu10, cpu5, cpu11`): Unlocked to **4.50 GHz** with `balance_performance`.
  * Cores 1 & 2 (`cpu1, cpu7, cpu2, cpu8`): Scaled to **4.20 GHz** with `balance_performance`.
  * Core 3 (`cpu3, cpu9`): Set to **3.70 GHz** with `balance_performance`.
  * Core 0 (`cpu0, cpu6`): Protected at **3.40 GHz** with `balance_power`.
  * *Result:* Instantaneous UI response, fluid browser scrolling, and rapid single-threaded execution.
* **Heavy Multithread Profile (> 84°C Package Temperature):**
  * Cores 4 & 5: Held at **3.60 GHz** with `balance_performance`.
  * Cores 1 & 2: Held at **3.50 GHz** with `balance_performance`.
  * Core 3: Held at **3.40 GHz** with `balance_performance`.
  * Core 0: Protected at **3.10 GHz** with `balance_power`.
  * *Result:* Sustained ~3.40 GHz all-core frequency consuming ~42-45W. Zero PROCHOT events, zero scheduler thread migration churn, and maximum real throughput.

### 3. GPU Dynamic Auto + 3D Performance Profile
* AMD Radeon Pro DPM level configured to `auto`.
* Power Profile Mode set to `1 (3D_FULL_SCREEN)`.
* VRAM dynamically clocks between 95 MHz at idle and **750 MHz** under display load, providing fluid multi-monitor rendering.

### 4. Memory & I/O Optimization
* `zswap` enabled in RAM with `lz4` compression and a 25% pool limit.
* `vm.swappiness` reduced to 15, bypassing SSD I/O bottlenecks.

### 5. i915 Disconnected Connector Polling Disabled
* Disabled hotplug polling on inactive Intel integrated connectors, eliminating kernel workqueue latency stalls.

---

## 4. Verification & Benchmark Results

### Telemetry Comparison Matrix

| Metric | Factory State (Stock) | With Dynamic Watchdog Tuning |
| :--- | :--- | :--- |
| **Idle CPU Power (`PCPT`)** | 18.88W – 26.05W | **4.10W** |
| **Idle Core Temperatures** | 74°C – 91°C | **65°C – 67°C** |
| **Heavy Burst Load Behavior** | Core 0 hits 100°C in 180 ms | **Core 4/5 boost to 4.5 GHz; Core 0 stays at 74°C** |
| **Sustained Multithread Clocks** | Throttles to 800 MHz – 1.8 GHz | **Solid ~3.40 GHz synchronized** |
| **PROCHOT Throttle Events** | 35,292 in 77 minutes | **0 events (Rock solid stability)** |
| **AMD GPU VRAM Clock** | Clamped at 95 MHz (`low`) | **Dynamic 95–750 MHz (Full 3D profile)** |
| **Available System RAM** | 3.4 GiB | **6.7 GiB (ZSWAP LZ4 active)** |
| **i915 Kernel Workqueue Stalls** | 131+ stalls (>10 ms) | **0 stalls** |

---

## 5. Architectural Comparison: Why This is Impossible on macOS

Under macOS, this granular tuning cannot be achieved due to closed kernel policies:
1. **Monolithic Clock Scaling:** macOS's `X86PlatformPlugin` manages CPU power as a unified entity. Individual core MSR registers cannot be isolated without being overwritten by kernel power management.
2. **Aggressive `kernel_task` Throttling:** Under macOS, if Core 0 touches 100°C for even a split second, `kernel_task` artificially injects phantom idle cycles, throttling **all 6 cores down to 800 MHz**.
3. **No Granular Hardware Offsets:** macOS provides no public interface to program TCC Offset, custom RAPL clamps, or discrete GPU power profile modes.
