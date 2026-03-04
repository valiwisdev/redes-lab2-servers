# 🌐 Redes Lab 2 — Servidores

Repositorio del laboratorio 2 para **REDES Y SERVICIOS DE COMUNICACIONES**.
Contiene los scripts y configuraciones para los servicios DNS, FTP, Web (Nginx) y RTMP.

---

## 📁 Estructura del repositorio

```
redes-lab2-servers/
├── dns-server/
│   └── setup_dns.sh
├── extras/
│   ├── install_docker.sh
│   └── set_static_ip.sh
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
└── installer.sh
```

---

## 🚀 Instalación — usando el instalador interactivo

El script `installer.sh` centraliza la configuración de todos los servicios en un único menú interactivo. Es la forma recomendada de configurar el laboratorio.

```bash
sudo bash installer.sh
```

El menú muestra el estado de cada servicio en tiempo real (`●` activo / `○` inactivo) y permite configurar cada uno sin necesidad de navegar manualmente por los directorios.

```
  Select a service to configure:

  ────────────────────────────────────────────────
   1)  ●  Docker                   required for 2, 3, 4
  ────────────────────────────────────────────────
   2)  ○  FTP Server               ProFTPD · ports 21, 30000-30009
   3)  ○  Web Server               Nginx · ports 80, 443 (SSL)
   4)  ○  RTMP Server              Nginx-RTMP + ffmpeg · 80, 1935
  ────────────────────────────────────────────────
   5)  ○  DNS Server               BIND9 · no Docker needed
  ────────────────────────────────────────────────
   q)  Quit
```

> **Orden recomendado:** configura primero FTP, Web y RTMP con su IP estática. El DNS se configura de último. Las verificaciones con `nslookup`, `curl` y `ftp` se hacen al final, una vez que el DNS esté activo.

---

## 🔵 Servicios

### 🔹 1 — FTP Server

**ProFTPD** en Docker. Opera en modo pasivo (puertos `30000–30009`) con el canal de control en el `21`.

Desde el instalador → opción **`2`**, subopción **`a`** (configura y levanta el contenedor).

El instalador pedirá:
- **FTP username** (default: `ftpuser`)
- **FTP password** (default: `ftppassword`)
- **IP del servidor** para el modo pasivo (se detecta automáticamente)

Para ver logs, subopción **`b`**. Para configurar IP estática, subopción **`c`**.

---

### 🔹 2 — Web Server

**Nginx** (`nginx:alpine`) sirviendo una página HTML en HTTP (puerto `80`) y HTTPS (puerto `443`) con certificado SSL autofirmado generado con OpenSSL.

Desde el instalador → opción **`3`**, subopción **`a`** (genera el certificado y levanta el contenedor).

> Los certificados están en `.gitignore` — el instalador los genera automáticamente si no existen. Se puede regenerar el certificado si la IP del servidor cambió.

Para ver logs, subopción **`b`**. Para configurar IP estática, subopción **`c`**.

---

### 🔹 3 — RTMP Server

Dos contenedores Docker:
- **`rtmp-nginx`** — Nginx con módulo RTMP, escucha en el puerto `1935` (stream) y `80` (health check).
- **`ffmpeg-publisher`** — Toma el video de `rtmp-server/videos/` y lo publica en loop al servidor.

Desde el instalador → opción **`4`**, subopción **`a`** (configura stream key, video y levanta los contenedores).

El instalador pedirá:
- **Stream key** (default: `1`)
- **Video file** — nombre del archivo en `rtmp-server/videos/` (default: `IVE.mp4`)

> Coloca tu archivo de video en `rtmp-server/videos/` antes de iniciar.

Para ver logs, subopción **`b`**. Para configurar IP estática, subopción **`c`**.

---

### 🔹 4 — DNS Server

**BIND9** instalado directamente en la VM (sin Docker). Gestiona el dominio `labredesXY.com` con zona directa (registros A) y zona inversa (registros PTR).

Desde el instalador → opción **`5`**:

| Subopción | Acción |
|---|---|
| `a` | Instala BIND9 si no está instalado |
| `b` | Configuración guiada completa (primera vez) |
| `c` | Agregar o actualizar un registro (`--add`) |
| `d` | Ver registros actuales (`--list`) |
| `e` | Configurar IP estática |

El setup pedirá número de grupo, sección, IP del servidor DNS (se detecta automáticamente), y opcionalmente las IPs de Web y FTP (se pueden agregar después con la subopción `c`).

También se puede ejecutar directamente:

```bash
sudo bash dns-server/setup_dns.sh        # Instalación guiada interactiva
sudo bash dns-server/setup_dns.sh --add  # Agregar o actualizar un registro
sudo bash dns-server/setup_dns.sh --list # Ver registros actuales
```

---

## 💻 Configuración del cliente DNS en Omarchy Linux

Una vez que todos los servicios están levantados, configura las VMs cliente para que usen el servidor DNS del laboratorio.

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

> **Nota:** `resolv.conf` mostrará `nameserver 127.0.0.53` — es normal. Verifica con `resolvectl status` para confirmar que apunta a la IP del lab.

### Paso 2 — Instalar nslookup

```bash
sudo pacman -S bind-tools
```

---

## ✅ Verificación de servicios

### DNS
```bash
nslookup dns.labredesXY.com 192.168.74.147
nslookup web.labredesXY.com 192.168.74.147
nslookup ftp.labredesXY.com 192.168.74.147
nslookup 192.168.74.147 192.168.74.147   # PTR inverso
```

### Web (Nginx)
```bash
curl http://web.labredesXY.com
curl -k https://web.labredesXY.com
```

### FTP
```bash
ftp ftp.labredesXY.com
```

### RTMP
Abre VLC u OBS y conecta a:
```
rtmp://<IP_SERVIDOR>/live/<STREAM_KEY>
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
| DNS | `dns.labredesXY.com` | `X.X.X.X` |
| Web | `web.labredesXY.com` | `X.X.X.X` |
| FTP | `ftp.labredesXY.com` | `X.X.X.X` |

> Reemplaza `XY` con tu número de grupo y sección, y completa las IPs reales.