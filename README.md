# 🌐 Redes Lab 2 — Servidores

Repositorio del laboratorio 2 para **Infraestructura de Comunicaciones**.
Contiene los scripts y configuraciones para los servicios DNS, FTP, Web (Nginx) y RTMP.

---

## 📁 Estructura del repositorio

```
redes-lab2-servers/
├── dns-server/
│   └── setup_dns.sh
├── ftp-server/
│   └── setup_ftp.sh
├── nginx-server/
│   ├── docker-compose.yml
│   ├── nginx.conf
│   ├── gen_certs.sh
│   ├── html/
│   │   └── index.html
│   └── README.md
├── rtmp-server/
│   ├── docker-compose.yml
│   ├── .env
│   ├── videos/
│   │   └── IVE.mp4
│   └── nginx/
│       ├── Dockerfile
│       └── nginx.conf
├── install_docker.sh
└── set_static_ip.sh
```

---

## ⚙️ Antes de empezar

### Instalar Docker (requerido para nginx y rtmp)
```bash
sudo bash install_docker.sh
```

---

## 🔵 Servicios

### 🔹 DNS Server — `dns-server/`

Servidor de nombres basado en **BIND9** con zonas directa e inversa para `labredesXY.com`.

Registros configurados: `dns`, `web` y `ftp`.

#### Instalar BIND9 manualmente
```bash
sudo apt-get update
sudo apt-get install -y bind9 bind9utils bind9-doc dnsutils
```

#### Verificar instalación
```bash
named -v
systemctl status named
```

```bash
sudo bash dns-server/setup_dns.sh              # Instalación guiada interactiva
sudo bash dns-server/setup_dns.sh --add        # Agregar o actualizar un registro
sudo bash dns-server/setup_dns.sh --list       # Ver registros actuales
sudo bash dns-server/setup_dns.sh --status     # Estado del servicio y prueba de resolución
```

#### IP estática
```bash
sudo bash set_static_ip.sh
```

---

### 🔹 FTP Server — `ftp-server/`

Servidor FTP para transferencia de archivos dentro de la red del laboratorio.

```bash
sudo bash ftp-server/setup_ftp.sh
```

#### IP estática
```bash
sudo bash set_static_ip.sh
```

---

### 🔹 Web Server — `nginx-server/`

Servidor web **Nginx en Docker** con soporte HTTP (puerto `80`) y HTTPS (puerto `443`) mediante certificado SSL autofirmado.

#### Paso 1 — Generar el certificado SSL
```bash
bash nginx-server/gen_certs.sh
```

#### Paso 2 — Levantar el servidor
```bash
cd nginx-server
docker compose up -d
```

#### Verificar
```bash
curl http://web.labredesXY.com
curl -k https://web.labredesXY.com
```

#### IP estática
```bash
sudo bash set_static_ip.sh
```

---

### 🔹 RTMP Server — `rtmp-server/`

Servidor de streaming en tiempo real usando **Nginx + módulo RTMP** en Docker.

#### Paso 1 — Configurar variables en `.env`
```dotenv
STREAM_KEY=1
VIDEO_FILE=IVE.mp4
```

> Coloca el archivo de video en `rtmp-server/videos/` y actualiza `VIDEO_FILE` con su nombre.

#### Paso 2 — Levantar el servidor
```bash
cd rtmp-server
docker compose up -d
```

#### URL de stream
```
rtmp://<IP_SERVIDOR>/live/<STREAM_KEY>
```

#### IP estática
```bash
sudo bash set_static_ip.sh
```

---

## 💻 Configuración del cliente DNS en Omarchy Linux

Después de levantar el servidor DNS, configura las demás VMs para que lo usen.

### Paso 1 — Editar configuración de systemd-resolved

```bash
sudo nano /etc/systemd/resolved.conf
```

```ini
[Resolve]
DNS=192.168.74.147
Domains=labredesXY.com
LLMNR=no
MulticastDNS=no
DNSSEC=no
```

```bash
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

> **Nota:** `resolv.conf` mostrará `nameserver 127.0.0.53` — es normal, systemd actúa como intermediario.
> Verifica con `resolvectl status` para confirmar que apunta a tu IP del lab.

---

### Paso 2 — Instalar nslookup
```bash
sudo pacman -S bind-tools
```

### Paso 3 — Probar resolución
```bash
# Resolución directa
nslookup dns.labredesXY.com 192.168.74.147
nslookup web.labredesXY.com 192.168.74.147
nslookup ftp.labredesXY.com 192.168.74.147

# Resolución inversa (PTR)
nslookup 192.168.74.147 192.168.74.147
```

---

### ⚠️ Restaurar DNS al terminar el laboratorio

```bash
sudo nano /etc/systemd/resolved.conf
# Comentar o borrar: DNS= y Domains=
sudo systemctl restart systemd-resolved
```

---

## 📋 IPs del laboratorio

| Servicio | Hostname | IP |
|---|---|---|
| DNS | `dns.labredesXY.com` | `192.168.X.X` |
| Web | `web.labredesXY.com` | `192.168.X.X` |
| FTP | `ftp.labredesXY.com` | `192.168.X.X` |

> Reemplaza `XY` con tu número de grupo y sección, y completa las IPs reales.

---
