#!/bin/bash
set -e

echo "=========================================================================="
echo " MacBook Pro 16,1 (A2141) Tuning Uninstaller"
echo "=========================================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[-] Ejecuta como root: sudo ./uninstall.sh"
  exit 1
fi

echo "[*] Deshabilitando y eliminando servicio systemd y sleep hook..."
systemctl disable --now macbook-a2141-tuning.service 2>/dev/null || true
rm -f /etc/systemd/system/macbook-a2141-tuning.service
rm -f /lib/systemd/system-sleep/macbook-a2141-tuning-sleep
rm -f /usr/local/sbin/macbook-a2141-tuning.sh
systemctl daemon-reload

echo "[*] Eliminando configuraciones de sysctl y udev..."
rm -f /etc/sysctl.d/99-a2141-memory.conf
rm -f /etc/udev/rules.d/30-amdgpu-pm.rules
udevadm control --reload-rules || true

echo "[+] Desinstalación completada. Se restaurarán los valores por defecto tras reiniciar."
