# Issue: Intel i915 workqueue latency (>10000us) on dual-GPU T2 Macs due to continuous polling on disconnected outputs

## Affected Hardware
* **Model:** Apple MacBookPro16,1 (A2141, 16-inch 2019)
* **CPU:** Intel Core i7-9750H / i9-9880H (Intel UHD Graphics 630)
* **dGPU:** AMD Radeon Pro 5300M / 5500M
* **Kernel:** 7.x-t2-noble (Ubuntu 24.04 LTS)

## Bug Description
On dual-GPU MacBookPro models where the display server runs exclusively on the discrete AMD GPU (`card2`), the Intel integrated graphics card (`card1` / `i915`) continuously runs hotplug detection polling on its disconnected DP and HDMI ports.
This causes recurring workqueue stalls that block CPU threads for over 10 ms:

```
workqueue: output_poll_execute hogged CPU for >10000us 131 times, consider switching to WQ_UNBOUND
workqueue: i915_hpd_poll_init_work [i915] hogged CPU for >10000us 131 times, consider switching to WQ_UNBOUND
```

## Impact
Noticeable micro-stutters and input lag spikes during desktop usage.

## Tested Workaround / Fix
Forcing disconnected connectors on the i915 device node to `off` completely eliminates the CPU-hogging workqueue warning and restores smooth frame pacing:

```bash
for conn in /sys/class/drm/card*-DP-*/status /sys/class/drm/card*-HDMI-*/status; do
    if [ -f "$conn" ]; then
        card_dir=$(dirname "$conn")
        driver_link=$(readlink -f "$card_dir/device/driver" 2>/dev/null || true)
        if [[ "$driver_link" == *"i915" ]]; then
            echo off > "$conn" 2>/dev/null || true
        fi
    fi
done
```

Proposed integration: This could be packaged as a default udev or kernel module parameter workaround for dual-GPU T2 models in `t2-ubuntu-repo`.
