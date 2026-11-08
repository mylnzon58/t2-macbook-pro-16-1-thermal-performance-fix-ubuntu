#!/bin/bash
set -e

echo "=========================================================================="
echo " MacBook Pro 16,1 (A2141) Thermal & Performance Kernel Tuning Installer"
echo " Author: Juan José Monzón (@mylnzon58)"
echo "=========================================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root: sudo ./install.sh"
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "[+] 1. Copiando script de optimización a /usr/local/sbin/..."
cp "$SCRIPT_DIR/config/macbook-a2141-tuning.sh" /usr/local/sbin/macbook-a2141-tuning.sh
chmod +x /usr/local/sbin/macbook-a2141-tuning.sh

echo "[+] 2. Configurando servicio persistente systemd..."
cp "$SCRIPT_DIR/config/macbook-a2141-tuning.service" /etc/systemd/system/macbook-a2141-tuning.service
systemctl daemon-reload
systemctl enable --now macbook-a2141-tuning.service

echo "[+] 3. Configurando gancho post-suspensión para persistencia al despertar..."
cp "$SCRIPT_DIR/config/macbook-a2141-tuning-sleep" /lib/systemd/system-sleep/macbook-a2141-tuning-sleep
chmod +x /lib/systemd/system-sleep/macbook-a2141-tuning-sleep

echo "[+] 4. Configurando optimización de memoria (swappiness=15)..."
cp "$SCRIPT_DIR/config/99-a2141-memory.conf" /etc/sysctl.d/99-a2141-memory.conf
sysctl -p /etc/sysctl.d/99-a2141-memory.conf

echo "[+] 5. Limpiando reglas udev redundantes..."
rm -f /etc/udev/rules.d/30-amdgpu-pm.rules
udevadm control --reload-rules || true

echo "[+] 6. Ejecutando sintonización en vivo..."
/usr/local/sbin/macbook-a2141-tuning.sh

echo "=========================================================================="
echo " [+] ¡Instalación completada con éxito!"
echo " Tu MacBook Pro 16,1 ahora corre con Turbo Asimétrico por Núcleo (4.5 GHz)"
echo " y el Core 0 protegido contra thermal throttling."
echo "--------------------------------------------------------------------------"
echo " 💙 Mensaje del autor / Author's note:"
echo " Soy Juan José Monzón (@mylnzon58), desarrollador argentino y padre de una niña y un niño pequeño."
echo " Intento vivir de lo que amo (el desarrollo de software y tecnología), y quise compartir"
echo " esta solución de forma abierta para ayudar a quienes tienen este modelo de Mac con Linux."
echo ""
echo " ⭐ Si esta optimización enfrió tu Mac y mejoró su rendimiento en Linux, déjame una estrella en GitHub:"
echo " 👉 https://github.com/mylnzon58/t2-macbook-pro-16-1-thermal-performance-fix-ubuntu"
echo " ¡Muchas gracias por tu apoyo! / Thank you for your support!"
echo "=========================================================================="
