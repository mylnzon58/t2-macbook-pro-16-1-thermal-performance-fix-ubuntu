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
  * When Linux intel_pstate allows the processor to boost aggressively, it attempts to pull over 90W on an already warm copper heatpipe, causing instantaneous thermal runaway.

### Problem 4: AMD Radeon Pro dGPU Locked to `low` Performance Mode (95 MHz VRAM)
* **Symptom:** Severe desktop stuttering, window dragging lag, and dropped frames with dual displays connected (`eDP-1` internal display + external DisplayPort `DP-6`).
* **Configuration Root Cause:**
  * A legacy udev rule (`/etc/udev/rules.d/30-amdgpu-pm.rules`) forced `power_dpm_force_performance_level="low"`.
  * This locked the AMD Radeon Pro 5300M memory clock (`mclk`) strictly to **95 MHz** (down from its 750 MHz rated clock) and the GPU core (`sclk`) to **300 MHz**.
  * While intended to reduce power draw, driving two displays at 95 MHz VRAM crippled display pipeline bandwidth without reducing idle power: the dGPU still consumed **17.9W–19.1W of static power** (`PG0R`).

### Problem 5: Intel i915 Disconnected Display Polling Kernel Stalls (>10 ms Workqueue Freeze)
* **Symptom:** Micro-stutters and recurring input latency every few seconds.
* **Kernel Driver Root Cause:**
  * Because the machine runs with the AMD dGPU handling active displays, the Intel UHD 630 iGPU (`card1`) has all external connectors in a `disconnected` state.
  * The Linux `i915` display driver continuously scheduled hotplug polling (`i915_hpd_poll_init_work`), causing workqueue stalls that blocked CPU threads:
    `workqueue: output_poll_execute hogged CPU for >10000us 131 times`
    `workqueue: i915_hpd_poll_init_work [i915] hogged CPU for >10000us 131 times`

### Problem 6: Dormant `zswap` and NVMe I/O Queue Bottleneck
* **Symptom:** High application memory latency and disk thrashing when running development workloads (Chrome, IDEs).
* **OS / Kernel Root Cause:**
  * Although GRUB parameters specified `zswap.enabled=1`, the runtime kernel parameter was disabled (`/sys/module/zswap/parameters/enabled = N`) with the slow `lzo` compressor.
  * The system utilized a modest 2GB `/swapfile` on disk with a default `vm.swappiness` of `60`.
  * The Apple T2 NVMe storage architecture exposes only a single hardware I/O queue (`queue_count = 2`: 1 admin + 1 I/O) to the Linux driver. Heavy anonymous memory paging into disk saturated this single queue, causing **17.3 million I/O pressure stalls** (`/proc/pressure/io`).

### Problem 7: Runaway Background Runtimes (GradleDaemon CPU/RAM Drain)
* **Symptom:** Elevated baseline CPU temperatures (65–70°C) with zero user activity.
* **Process Root Cause:**
  * An orphaned `GradleDaemon 8.14` background process (PID `8473`, JDK 17) was continuously consuming **15.1% of CPU time** and **1.43 GB of resident RAM**, preventing the processor from dropping into low-power C-states.

### Problem 8: Battery Health Degradation & Dynamic AC Charger Sag
* **Hardware Condition:**
  * Battery cycle count: **586 cycles**.
  * Full charge capacity: **6,796 mAh (85.7 Wh)** vs. design capacity of **8,790 mAh (99.8 Wh)** — **77.3% remaining health**.
  * A replacement generic 89.9W USB-C charger negotiated insufficient wattage during peak combined loads (CPU 50W + GPU 20W + displays/logic 25W), forcing the SMC to dynamically drain between **-418 mA and -1.93 A** from the battery while plugged in, generating battery self-heating.

---

## 3. Evolution of Applied Solutions

### Phase 1: The Initial Conservative Approach (Symmetric Capping)
In the first optimization phase, we applied a standard conservative profile:
* Global RAPL limits clamped to **35W PL1 / 45W PL2**.
* Global CPU clock ceiling clamped symmetrically across all 6 cores to **3.60 GHz**.
* AMD GPU DPM switched to `auto`.
* Orphaned Gradle daemon terminated; `zswap` enabled with `lz4`.

**Why the User Requested a Change:**
While this completely prevented Core 0 from hitting 100°C, a symmetric 3.6 GHz cap on all cores penalized single-core burst throughput. The user explicitly stated: *"I do not want to sacrifice power; I want this Mac to perform at its true high-performance potential, faster on Ubuntu than on macOS."*

---

### Phase 2: The Final Asymmetric Architecture (Per-Core HWP + TCC Modulation)
To maximize computing throughput while respecting the physical thermal defect of Core 0, we designed and deployed a **hardware-level asymmetric allocation**:

1. **Per-Core HWP Turbo Allocation (`intel_pstate`):**
   * **Core 4 & Core 5 (Logical cpu4, cpu10, cpu5, cpu11):** Unlocked to maximum factory turbo: **4.50 GHz** with `balance_performance`. These cores have optimal heatsink contact and handle intensive single- and dual-threaded workloads.
   * **Core 1 & Core 2 (Logical cpu1, cpu7, cpu2, cpu8):** Configured to **4.20 GHz** with `balance_performance`.
   * **Core 3 (Logical cpu3, cpu9):** Configured to **3.70 GHz** with `balance_power`.
   * **Core 0 (Logical cpu0, cpu6):** Isolated and capped at **3.40 GHz** with `balance_power`. This prevents Core 0 from entering high-voltage turbo states (`>1.25V`), eliminating the trigger for package-wide PROCHOT.

2. **Total Package Power Limits (RAPL):**
   * Sustained Power (`constraint_0` / PL1): **52.00W** (exceeds Intel's 45W factory TDP for sustained multi-core heavy lifting).
   * Short Burst Power (`constraint_1` / PL2): **65.00W** (well within the chassis' 82W combined cooling limit).

3. **Hardware TCC Offset Modulation (Cooling Device 18):**
   * Configured `/sys/class/thermal/cooling_device18/cur_state = 3`.
   * This lowers the hardware thermal modulation trip point by 3°C (from 100°C to **97°C**). The Intel CPU automatically modulates clock frequency in **microseconds** via Speed Shift if 97°C is touched, completely bypassing the catastrophic system freeze of emergency PROCHOT.

4. **AMD GPU Optimization (Dynamic Auto + 3D Profile):**
   * Set DPM level to `auto` across all cards.
   * Configured Power Profile Mode `1 (3D_FULL_SCREEN)` in `/sys/class/drm/card2/device/pp_power_profile_mode`.
   * The GPU drops core and memory clocks to low power at idle, but instantly ramps memory to **750 MHz** and core to **1250 MHz** when rendering windows across dual monitors.

5. **Elimination of i915 Polling Lag:**
   * Disabled display hotplug polling on all inactive connectors on the Intel integrated card (`card1-DP-*` and `card1-HDMI-*`).

6. **In-RAM Compressed Swap (`zswap` + `lz4` + `swappiness=15`):**
   * Activated `zswap` with `lz4` compression and a 25% pool limit.
   * Decreased `vm.swappiness` from 60 to 15, keeping memory operations inside compressed RAM and bypassing the single-queue NVMe bottleneck.

7. **Systemd Persistence:**
   * Created `/usr/local/sbin/macbook-a2141-tuning.sh` and enabled `/etc/systemd/system/macbook-a2141-tuning.service`.

---

## 4. Verification & Benchmark Results

### Telemetry Comparison Matrix

| Metric | Factory / Unoptimized State | Initial Conservative Tuning | Final Asymmetric Architecture |
| :--- | :--- | :--- | :--- |
| **Idle CPU Power (`PCPT`)** | 18.88W – 26.05W | 4.90W | **4.10W** |
| **Idle Core 0 / Core 4 Temp** | 74°C / 79°C | 65°C / 65°C | **67°C / 65°C** |
| **Heavy Burst Load Behavior** | Core 0 hits 100°C in 180ms | All cores capped at 3.6 GHz | **Core 4/5 boost to 4.5 GHz; Core 0 stays at 74°C** |
| **PROCHOT Throttle Events** | 35,292 in 77 minutes | 0 new events | **0 new events (Rock solid stability)** |
| **AMD GPU VRAM Clock** | Fixed at 95 MHz (`low`) | Dynamic up to 750 MHz (`auto`) | **Dynamic 95–750 MHz with 3D Profile 1** |
| **Available RAM** | 3.4 GiB | 6.7 GiB | **6.7 GiB** |
| **i915 Kernel Latency Stalls** | 131+ stalls (>10ms each) | Eliminated | **Eliminated (0 stalls)** |

---

## 5. Architectural Comparison: Why This is Impossible on macOS

Under macOS, this granular tuning cannot be achieved due to closed kernel policies:
1. **Monolithic Clock Scaling:** macOS's `X86PlatformPlugin` manages CPU power as a unified entity. Individual core MSR registers (`MSR 0x774`) cannot be isolated without being overwritten by kernel power management.
2. **Aggressive `kernel_task` Throttling:** Under macOS, if Core 0 touches 100°C for even a split second, `kernel_task` artificially injects phantom idle cycles, throttling **all 6 cores down to 800 MHz**.
3. **No Granular Hardware Offsets:** macOS provides no public interface to program TCC Offset or tune AMD discrete GPU power profile modes.
