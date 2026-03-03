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

### 1. Dar permisos a los scripts
```bash
chmod +x set_static_ip.sh
chmod +x install_docker.sh
chmod +x dns-server/setup_dns.sh
chmod +x ftp-server/setup_ftp.sh
chmod +x nginx-server/gen_certs.sh
```

### 2. Instalar Docker (requerido para FTP, Nginx y RTMP)

Docker se instala usando el script `install_docker.sh`, que agrega el repositorio oficial de Docker, instala `docker-ce`, `docker-ce-cli`, `containerd.io` y los plugins de `buildx` y `compose`, y agrega el usuario actual al grupo `docker`.

```bash
sudo bash install_docker.sh
```

> Después de instalar, cierra sesión y vuelve a entrar, o ejecuta `newgrp docker` para que los cambios de grupo tomen efecto. Verifica con `docker run hello-world`.

---

## 🔵 Servicios

> **Orden recomendado:** configura primero FTP, Web y RTMP con su IP estática. El DNS se configura de último. Las verificaciones con `nslookup`, `curl` y `ftp` se hacen al final, una vez que el DNS esté activo y configurado en el cliente.

---

### 🔹 FTP Server — `ftp-server/`

**FTP (File Transfer Protocol)** permite transferir archivos entre máquinas de la red. Este servidor usa **ProFTPD** corriendo en un contenedor **Docker**. El script `setup_ftp.sh` genera automáticamente el `Dockerfile`, la configuración de ProFTPD y el `docker-compose.yml` según los valores que ingreses, y levanta el contenedor.

El servidor opera en **modo pasivo** (puertos `30000–30009`) con el puerto de control en `21`.

#### Ejecutar el script
```bash
sudo bash ftp-server/setup_ftp.sh
```

El script te pedirá:
- **FTP username** (default: `ftpuser`)
- **FTP password** (default: `ftppassword`)
- **IP del servidor** para el modo pasivo (se detecta automáticamente)

#### Ver logs
```bash
docker compose logs proftpd
```

#### IP estática
```bash
sudo bash set_static_ip.sh
```

El script detecta automáticamente la interfaz de red y la IP actual por DHCP, y te permite confirmar o cambiar los valores antes de aplicarlos via `netplan`.

---

### 🔹 Web Server — `nginx-server/`

**Nginx** es un servidor web de alto rendimiento. En este laboratorio sirve una página HTML en HTTP (puerto `80`) y HTTPS (puerto `443`) con un certificado SSL autofirmado generado con OpenSSL. Corre en Docker usando la imagen `nginx:alpine`.

La configuración en `nginx.conf` define dos bloques `server`: uno para HTTP y otro para HTTPS con TLS 1.2/1.3. La página servida está en `html/index.html`.

> **Nota:** Los certificados están en `.gitignore` (`certs/`, `*.key`, `*.crt`, `*.pem`) — hay que generarlos antes de levantar el servidor.

#### Paso 1 — Generar el certificado SSL

El script `gen_certs.sh` detecta automáticamente la IP de la VM y genera un certificado autofirmado RSA 2048 válido por 365 días en `certs/server.key` y `certs/server.crt`.

```bash
bash nginx-server/gen_certs.sh
```

#### Paso 2 — Levantar el servidor
```bash
cd nginx-server
docker compose up -d
```

#### IP estática
```bash
sudo bash set_static_ip.sh
```

---

### 🔹 RTMP Server — `rtmp-server/`

**RTMP (Real-Time Messaging Protocol)** es un protocolo para transmisión de video y audio en tiempo real. Este servidor usa dos contenedores Docker:

- **`rtmp-nginx`**: Nginx con el módulo RTMP, escucha en el puerto `1935` (stream) y `80` (HTTP health check).
- **`ffmpeg-publisher`**: Toma el archivo de video de `videos/`, lo codifica con `libx264`/`aac` y lo publica en loop al servidor RTMP automáticamente.

#### Paso 1 — Configurar el archivo `.env`

```dotenv
STREAM_KEY=1
VIDEO_FILE=IVE.mp4
```

- `STREAM_KEY`: clave del stream (se usa en la URL de reproducción).
- `VIDEO_FILE`: nombre del archivo de video en `rtmp-server/videos/`.

> Coloca tu archivo de video en `rtmp-server/videos/` y actualiza `VIDEO_FILE` con su nombre.

#### Paso 2 — Levantar el servidor
```bash
cd rtmp-server
docker compose up -d
```

#### Ver logs
```bash
docker compose logs rtmp
docker compose logs publisher
```

#### IP estática
```bash
sudo bash set_static_ip.sh
```

---

### 🔹 DNS Server — `dns-server/`

**DNS (Domain Name System)** traduce nombres de dominio en direcciones IP y viceversa. En este laboratorio se usa **BIND9** para gestionar el dominio `labredesXY.com` con dos zonas:

- **Zona directa**: resuelve `dns.labredesXY.com`, `web.labredesXY.com` y `ftp.labredesXY.com` a sus IPs.
- **Zona inversa**: resuelve IPs de vuelta a sus nombres (registros PTR).

El script `setup_dns.sh` es interactivo: detecta automáticamente la IP del servidor DNS, permite omitir registros que aún no estén disponibles y guardar el estado para agregarlos después.

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

#### Configurar con el script

```bash
sudo bash dns-server/setup_dns.sh        # Instalación guiada interactiva
sudo bash dns-server/setup_dns.sh --add  # Agregar o actualizar un registro (dns/web/ftp)
sudo bash dns-server/setup_dns.sh --list # Ver registros actuales
```

El script te pedirá:
- **Número de grupo** y **sección** para construir el dominio (`labredesXY.com`)
- **IP del servidor DNS** (se detecta automáticamente, puedes confirmar o cambiar)
- **IP del servidor Web** (opcional, se puede agregar después con `--add`)
- **IP del servidor FTP** (opcional, se puede agregar después con `--add`)

#### IP estática
```bash
sudo bash set_static_ip.sh
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

> **Nota:** `resolv.conf` mostrará `nameserver 127.0.0.53` — es normal, systemd actúa como intermediario. Verifica con `resolvectl status` para confirmar que apunta a tu IP del lab.

### Paso 2 — Instalar nslookup
```bash
sudo pacman -S bind-tools
```

---

## ✅ Verificación de servicios

Con el DNS configurado en el cliente, verifica que todos los servicios funcionan correctamente.

### DNS
```bash
# Resolución directa
nslookup dns.labredesXY.com 192.168.74.147
nslookup web.labredesXY.com 192.168.74.147
nslookup ftp.labredesXY.com 192.168.74.147

# Resolución inversa (PTR)
nslookup 192.168.74.147 192.168.74.147
```

### Web (Nginx)
```bash
curl http://web.labredesXY.com
curl -k https://web.labredesXY.com   # -k ignora el certificado autofirmado
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

---

**Infraestructura de Comunicaciones — Universidad de los Andes**
