# 📋 Preguntas y respuestas sobre los servicios

---

## ⚙️ `set_static_ip.sh`

**¿Por qué el script usa `ip -o -4 route show to default` para detectar la interfaz?**
Porque el nombre de la interfaz varía entre máquinas (`ens33`, `eth0`, `enp0s3`). Leer la tabla de rutas del sistema para encontrar la interfaz del gateway por defecto es la forma más portátil y confiable de detectarla sin hardcodear un nombre.

**¿Qué hace `sudo tee` y por qué se usa en vez de `>`?**
`tee` escribe en un archivo y también muestra el contenido en pantalla. Se usa en lugar de `>` porque la redirección `>` corre con los permisos del usuario actual, mientras que `sudo tee` escribe el archivo con permisos de root, que es necesario para modificar archivos en `/etc/netplan/`.

**¿Por qué se hace backup del archivo netplan antes de modificarlo?**
Porque si la configuración nueva tiene errores y el servidor pierde conectividad de red, se puede restaurar la configuración original desde el backup sin necesidad de acceso físico a la máquina.

**¿Qué pasaría si no existe ningún archivo `.yaml` en `/etc/netplan/`?**
El script detecta que `NETPLAN_FILE` queda vacío, imprime el mensaje `ERROR: No netplan YAML file found in /etc/netplan/` y termina con `exit 1`, sin modificar nada.

**¿Por qué se usa `dhcp4: no` y no se configuran nameservers?**
El laboratorio solo pide configurar Address, Netmask y Gateway según la guía. El DNS se configura por separado en la VM cliente mediante `systemd-resolved`, apuntando al servidor BIND9 del laboratorio.

---

## 🐳 `install_docker.sh`

**¿Por qué se agrega el repositorio oficial de Docker y no se usa `apt install docker.io`?**
El paquete `docker.io` de Ubuntu es mantenido por Canonical y suele estar desactualizado. El repositorio oficial de Docker siempre tiene la versión más reciente con todos los plugins (`buildx`, `compose`) y soporte activo.

**¿Qué hace `sudo groupadd docker 2>/dev/null || true` y por qué el `|| true`?**
Intenta crear el grupo `docker`. Si el grupo ya existe, `groupadd` devuelve un error — el `|| true` hace que el script no falle en ese caso y continúe ejecutándose. El `2>/dev/null` silencia el mensaje de error.

**¿Por qué hay que cerrar sesión y volver a entrar después de `usermod -aG docker`?**
Los grupos de un usuario se cargan al iniciar sesión. Agregar el usuario a un grupo solo tiene efecto en sesiones nuevas. Sin reiniciar la sesión, el usuario sigue sin tener el grupo `docker` activo y Docker seguirá pidiendo `sudo`.

**¿Qué diferencia hay entre `docker-compose-plugin` y `docker-compose` standalone?**
`docker-compose-plugin` es el plugin oficial integrado en Docker CLI que se usa con `docker compose` (sin guión). El `docker-compose` standalone era una herramienta separada escrita en Python, ya deprecada. El plugin es más rápido, está mejor integrado y es el estándar actual.

---

## 📁 `ftp-server/setup_ftp.sh`

**¿Por qué el script genera el `Dockerfile` y `proftpd.conf` dinámicamente?**
Porque el usuario, la contraseña y la IP del servidor son valores que cambian entre grupos y entornos. Si los archivos fueran estáticos en el repositorio, habría que editarlos manualmente. El script los genera con los valores exactos ingresados, evitando errores de configuración.

**¿Por qué se usa `CMD ["proftpd", "--nodaemon"]`?**
Docker requiere que el proceso principal corra en primer plano. Por defecto ProFTPD se lanza como daemon en segundo plano — cuando eso ocurre, Docker cree que el proceso terminó y mata el contenedor inmediatamente. `--nodaemon` lo mantiene en primer plano.

**¿Qué hace `DefaultRoot /home/ftp/$FTPUSER $FTPUSER`?**
Aplica un chroot jail al usuario FTP. Cuando `ftpuser` se conecta, su directorio raíz queda restringido a `/home/ftp/ftpuser` y no puede navegar hacia directorios superiores del sistema de archivos. La segunda parte `$FTPUSER` indica que esta restricción aplica solo a ese usuario.

**¿Por qué se hace `chmod 777` a la carpeta `ftp_data`?**
El usuario dentro del contenedor (`ftpuser`) tiene un UID diferente al usuario del host. Sin permisos amplios, cuando ProFTPD intenta escribir en la carpeta mapeada como volumen, el sistema operativo lo rechaza con el error `550 Permission denied`.

**¿Por qué `MasqueradeAddress` debe ser la IP del host y no la del contenedor?**
En modo pasivo, el servidor le dice al cliente a qué IP conectarse para transferir datos. Dentro del contenedor, ProFTPD ve su IP interna de Docker (`172.17.x.x`). Si le pasa esa IP al cliente, el cliente intentará conectarse a una IP inalcanzable desde fuera del contenedor y la transferencia fallará. `MasqueradeAddress` sobreescribe eso con la IP real del host.

**¿Qué hace el bloque `<Limit LOGIN>`?**
Restringe quién puede iniciar sesión en el servidor FTP. `AllowUser $FTPUSER` permite solo al usuario configurado y `DenyAll` bloquea a todos los demás, incluyendo root, lo que mejora la seguridad del servidor.

**¿Por qué `docker compose up -d --build`?**
El flag `--build` fuerza a Docker a reconstruir la imagen desde el Dockerfile aunque ya exista una versión anterior. Es necesario porque el Dockerfile se genera dinámicamente con los valores del usuario — sin `--build` Docker usaría una imagen cacheada con valores incorrectos.

---

## 🌐 `nginx-server/`

**¿Por qué `nginx.conf` tiene dos bloques `server`, uno en el 80 y otro en el 443?**
Para servir la página tanto por HTTP como por HTTPS. El bloque del puerto 80 atiende tráfico no cifrado, el del 443 configura TLS con el certificado autofirmado. La guía del laboratorio pide que el sitio sea accesible por ambos protocolos.

**¿Por qué `ssl_protocols TLSv1.2 TLSv1.3` y no versiones anteriores?**
TLS 1.0 y 1.1 tienen vulnerabilidades conocidas (BEAST, POODLE) y están deprecados. Solo se habilitan 1.2 y 1.3 porque son los únicos considerados seguros actualmente.

**¿Por qué los certificados están en `.gitignore`?**
Los archivos `*.key`, `*.crt` y `*.pem` son sensibles. Subir una clave privada a un repositorio público es un riesgo de seguridad grave. Además, el certificado lleva la IP del servidor hardcodeada como CN — sería inútil para otras máquinas. Cada quien debe generarlo con `gen_certs.sh`.

**¿Por qué `gen_certs.sh` usa la IP detectada automáticamente como CN?**
El cliente verifica que el CN del certificado coincida con la dirección a la que se conecta. Si no coincide, el navegador rechaza la conexión TLS. Como el servidor se identifica por IP (no por dominio aún), el CN debe ser esa IP exacta.

**¿Por qué la imagen `nginx:alpine` y no `nginx:latest`?**
Alpine es una distribución Linux minimalista. La imagen pesa ~50MB versus ~180MB de la versión completa. Es más rápida de descargar, tiene menos superficie de ataque y es suficiente para servir archivos estáticos.

**¿Por qué el volumen de `nginx.conf` tiene `:ro`?**
`:ro` significa read-only. El contenedor puede leer la configuración pero no modificarla. Es una buena práctica de seguridad — si el proceso nginx dentro del contenedor fuera comprometido, no podría alterar su propia configuración.

---

## 📡 `rtmp-server/`

**¿Por qué hay dos contenedores, `rtmp-nginx` y `ffmpeg-publisher`?**
Separan responsabilidades: `rtmp-nginx` es el servidor que recibe y distribuye el stream, `ffmpeg-publisher` es el cliente que toma el video del archivo y lo publica al servidor. Esta separación permite reemplazar el publicador sin tocar el servidor, y viceversa.

**¿Qué hace `-stream_loop -1`?**
Le dice a ffmpeg que repita el archivo de video indefinidamente en loop. Sin esto, ffmpeg terminaría al acabar el video y el contenedor se detendría.

**¿Qué hace `-re` y por qué es necesario para RTMP?**
`-re` hace que ffmpeg lea el archivo a la velocidad de reproducción real (1x), en vez de procesarlo tan rápido como pueda. Sin `-re`, ffmpeg enviaría todo el video en segundos saturando el servidor RTMP, que no podría distribuirlo como stream en tiempo real.

**¿Por qué `publisher` tiene `depends_on: rtmp`?**
Para que Docker espere a que el contenedor `rtmp-nginx` esté levantado antes de iniciar `ffmpeg-publisher`. Sin esto, ffmpeg intentaría publicar al servidor antes de que esté listo y fallaría la conexión.

**¿Por qué `debian:bookworm-slim` y no Ubuntu?**
`libnginx-mod-rtmp` es el módulo RTMP para Nginx y está mejor empaquetado en Debian. Además `bookworm-slim` es ligero — tiene lo mínimo necesario para instalar Nginx con el módulo RTMP.

**¿Qué hace `load_module /usr/lib/nginx/modules/ngx_rtmp_module.so`?**
Carga dinámicamente el módulo RTMP en Nginx al arrancar. Nginx no trae RTMP integrado — es un módulo externo que se instala por separado (`libnginx-mod-rtmp`) y se activa con esta directiva al inicio del archivo de configuración.

**¿Por qué el servidor HTTP solo responde `"RTMP server OK"` en el puerto 80?**
El puerto 80 es solo un health check para verificar que el contenedor está vivo. El servicio real es RTMP en el puerto 1935. No se sirve contenido web real porque el propósito de este servidor es exclusivamente la transmisión de video.

**¿Qué significa `record off`?**
Le indica a Nginx que no guarde en disco una copia de los streams recibidos. Si estuviera en `on`, cada transmisión se grabaría como archivo en el servidor, consumiendo espacio innecesariamente para este laboratorio.

---

## 🌍 `dns-server/setup_dns.sh`

**¿Por qué el script tiene tres modos: setup, `--add` y `--list`?**
Porque en el laboratorio los servidores no se levantan todos al mismo tiempo. Se puede configurar BIND9 primero con solo el DNS, y luego agregar los registros de WEB y FTP cuando esos servidores estén listos, sin tener que reescribir toda la configuración desde cero.

**¿Por qué se deshabilita IPv6 con `OPTIONS="-u bind -4"`?**
La guía del laboratorio explícitamente indica usar solo IPv4. BIND9 por defecto escucha en IPv4 e IPv6 simultáneamente. Forzar `-4` evita conflictos con interfaces IPv6 que puedan no estar configuradas correctamente en el entorno del laboratorio.

**¿Qué es el número serial y por qué se actualiza con `bump_serial`?**
El serial es un número en el registro SOA de la zona que indica la versión de la configuración. Los servidores DNS secundarios lo usan para saber si deben sincronizarse con el primario. Debe incrementarse cada vez que se modifica la zona — si no se actualiza, los cambios no se propagan.

**¿Qué diferencia hay entre zona directa y zona inversa?**
La zona directa resuelve nombre → IP (ej. `web.labredes35.com` → `192.168.74.150`) mediante registros A. La zona inversa resuelve IP → nombre (ej. `192.168.74.150` → `web.labredes35.com`) mediante registros PTR. Ambas son necesarias para `nslookup` bidireccional.

**¿Por qué se guarda el estado en `/etc/bind/.dns_state`?**
Para que los modos `--add` y `--list` puedan recuperar el dominio, la red y las IPs configuradas durante el setup sin pedirlos de nuevo. Es un archivo de estado persistente que hace al script reutilizable entre sesiones.

**¿Qué hace `forwarders { 8.8.8.8; 8.8.4.4; }`?**
Configura a qué servidores DNS reenviar las consultas que BIND9 no puede resolver localmente (dominios fuera de `labredesXY.com`). Así el servidor DNS del lab también puede resolver dominios públicos como `google.com`, permitiendo que los clientes naveguen por internet mientras usan el DNS del laboratorio.

**¿Por qué se usa `named-checkzone` antes de recargar BIND9?**
Valida la sintaxis de los archivos de zona antes de aplicarlos. Si hay un error en la configuración y se recarga BIND9 sin validar, el servicio puede caerse completamente dejando a todos los clientes sin resolución DNS. `named-checkzone` actúa como una prueba de sanidad previa.

---

---

## 🔐 Certificados SSL/TLS

**¿Qué es un certificado SSL/TLS?**
Es un archivo digital que vincula una identidad (IP o dominio) con una clave pública. Permite que dos partes establezcan una conexión cifrada y que el cliente verifique que está hablando con quien cree que está hablando, no con un tercero que intercepta el tráfico.

**¿Qué diferencia hay entre un certificado autofirmado y uno de una CA reconocida?**
Un certificado de CA (como Let's Encrypt) está firmado por una autoridad en la que los navegadores confían por defecto. Un certificado autofirmado lo firma uno mismo — es técnicamente igual en cuanto al cifrado, pero el navegador no puede verificar su autenticidad y muestra advertencia. Para el laboratorio es suficiente porque controlamos tanto el servidor como el cliente.

**¿Qué contiene el par de archivos `server.key` y `server.crt`?**
`server.key` es la clave privada — nunca debe compartirse, por eso está en `.gitignore`. `server.crt` es el certificado público que contiene la clave pública, el CN (a quién pertenece), la fecha de expiración y la firma. El servidor usa ambos juntos para establecer TLS.

**¿Qué es RSA 2048 en el comando de `gen_certs.sh`?**
RSA es el algoritmo de cifrado asimétrico usado para generar el par de claves. 2048 es el tamaño en bits de la clave — a mayor tamaño, más seguro pero más lento. 2048 bits es el mínimo recomendado actualmente y es suficiente para un laboratorio.

**¿Qué significa `-days 365` en el comando de OpenSSL?**
Define la validez del certificado. Después de 365 días el certificado expira y los clientes lo rechazarán. En producción se usan certificados de 90 días (Let's Encrypt) o se automatizan las renovaciones.

**¿Qué es el CN (Common Name) y por qué en este lab es la IP y no un dominio?**
El CN identifica a quién pertenece el certificado. El cliente verifica que el CN coincida con la dirección a la que se conectó. En este lab se usa la IP porque al momento de generar el certificado el DNS todavía no está configurado. Una vez que el DNS esté activo, idealmente se regeneraría el certificado con el dominio como CN.

**¿Por qué `chmod 600` a `server.key`?**
Restringe la lectura de la clave privada solo al propietario. Si otros usuarios del sistema pudieran leerla, podrían descifrar todo el tráfico TLS del servidor o suplantar su identidad. Es una medida de seguridad básica para claves privadas.

**¿Qué pasa si el CN del certificado no coincide con la IP/dominio al que se conecta el cliente?**
El cliente rechaza la conexión TLS con un error de certificado. En el navegador aparece la advertencia "NET::ERR_CERT_COMMON_NAME_INVALID". FileZilla también lo rechaza a menos que se configure para ignorar errores de certificado.


---

## 🐳 ¿Por qué Docker y no instalación local?

**¿Cuál es la ventaja principal de usar Docker en este laboratorio?**
Aislamiento y reproducibilidad. El mismo `docker-compose.yml` funciona en cualquier máquina con Docker instalado, sin importar el sistema operativo o las librerías instaladas. Instalar ProFTPD, Nginx o Nginx-RTMP localmente puede fallar por dependencias faltantes o conflictos con otros paquetes del sistema.

**¿Qué pasaría si instaláramos ProFTPD directamente en la VM en vez de Docker?**
Habría que instalar con `apt`, editar manualmente `/etc/proftpd/proftpd.conf`, crear el usuario del sistema, gestionar el servicio con `systemctl`, y si algo falla es difícil volver al estado anterior. Con Docker, `docker compose down` destruye todo limpiamente y `docker compose up --build` lo recrea desde cero en segundos.

**¿Qué pasaría si instaláramos Nginx directamente en la VM?**
Habría que instalar Nginx, copiar manualmente el `nginx.conf`, copiar los certificados a la ruta correcta, y reiniciar el servicio con `systemctl`. Con Docker, todo eso está definido en el `docker-compose.yml` con los volúmenes mapeados — el contenedor arranca ya configurado sin pasos manuales adicionales.

**¿Qué pasaría si instaláramos el servidor RTMP directamente en la VM?**
Instalar `libnginx-mod-rtmp` requiere compilar Nginx con el módulo desde fuentes o usar un PPA externo, lo cual es propenso a errores y varía según la versión del sistema. Con Docker se usa un `Dockerfile` con `debian:bookworm-slim` donde el módulo está disponible directamente en los repositorios oficiales, haciendo la instalación reproducible y confiable.

**¿Por qué el servidor RTMP usa dos contenedores en vez de uno?**
Porque `rtmp-nginx` y `ffmpeg-publisher` tienen responsabilidades distintas. `rtmp-nginx` es el servidor que recibe y distribuye el stream. `ffmpeg-publisher` es el cliente que publica el video. Separarlos permite reemplazar el publicador o el servidor de forma independiente, y también permite que ffmpeg se reinicie solo si falla sin afectar el servidor RTMP.

**¿Por qué FTP usa un `Dockerfile` custom pero Nginx usa la imagen oficial `nginx:alpine`?**
Nginx sirve archivos estáticos y toda su configuración se puede pasar como volúmenes (`:nginx.conf`, `certs/`, `html/`). ProFTPD necesita crear un usuario del sistema con contraseña dentro del contenedor — eso requiere ejecutar `useradd` y `chpasswd` en el `Dockerfile`, algo que no se puede hacer con una imagen genérica.

**¿Por qué el RTMP tampoco usa una imagen oficial prebuilt?**
No existe una imagen oficial de Nginx con el módulo RTMP incluido. Se construye desde `debian:bookworm-slim` instalando `nginx` y `libnginx-mod-rtmp` explícitamente. Una imagen genérica de Nginx no tiene ese módulo y no hay forma de agregarlo sin construir la imagen.

**¿Cómo se actualiza la configuración de cada servicio con Docker?**
- **FTP**: se edita el script `setup_ftp.sh`, se ejecuta de nuevo y hace `docker compose up -d --build` para reconstruir la imagen con la nueva configuración.
- **Nginx web**: se edita `nginx.conf` o `html/index.html` y se reinicia con `docker compose restart` — no necesita rebuild porque la config se monta como volumen.
- **RTMP**: si se cambia `nginx.conf` también es solo restart; si se cambia el `Dockerfile` hay que hacer `--build`.

**¿Qué es el aislamiento de contenedores y por qué importa en este laboratorio?**
Cada contenedor tiene su propio sistema de archivos, procesos y red. Si ProFTPD dentro del contenedor fuera comprometido, no puede acceder a los archivos del host más allá de los volúmenes mapeados explícitamente (`./ftp_data`). Lo mismo aplica para Nginx — solo puede leer `nginx.conf`, `certs/` y `html/` porque son los únicos volúmenes definidos.

**¿Por qué todos los `docker-compose.yml` tienen `restart: unless-stopped`?**
Para que los contenedores se reinicien automáticamente si el proceso interno falla o si la VM se reinicia. `unless-stopped` significa que se reinicia siempre excepto cuando el usuario lo detiene manualmente con `docker compose down`. Es esencial para servidores que deben estar siempre disponibles durante el laboratorio.

**¿Qué ventaja tiene `docker compose logs` sobre revisar logs locales?**
Docker centraliza los logs de todos los servicios. Con `docker compose logs proftpd`, `docker compose logs rtmp` o `docker compose logs nginx` se puede ver la salida del proceso en tiempo real sin saber dónde guarda los logs cada servicio internamente. Sin Docker habría que buscar en `/var/log/proftpd/`, `/var/log/nginx/`, etc.

**¿Qué desventaja tiene Docker frente a instalación local en este contexto?**
La configuración de red es más compleja. Para FTP hay que gestionar la IP del host versus la IP interna del contenedor con `MasqueradeAddress`. Para RTMP hay que asegurarse de que ffmpeg se conecte al contenedor de Nginx por nombre interno (`rtmp://rtmp/...`). También agrega una capa de abstracción que puede dificultar el diagnóstico cuando algo falla.

## 🔌 ¿Cómo Docker abre y gestiona los puertos?

**¿Cómo funciona el mapeo de puertos en Docker (`ports: - "21:21"`)?**
Docker configura reglas en `iptables` del host que redirigen el tráfico que llega al puerto 21 del host hacia el puerto 21 del contenedor. El formato es `HOST:CONTENEDOR`. Cuando un cliente externo se conecta a `192.168.74.147:21`, iptables intercepta ese paquete y lo reenvía al contenedor.

**¿Por qué se mapean los puertos 30000-30009 además del 21?**
El puerto 21 es el canal de control FTP. Los puertos 30000-30009 son el canal de datos en modo pasivo. Cuando el cliente pide transferir un archivo, el servidor le dice "conéctate al puerto 300XX para los datos". Si esos puertos no están mapeados en Docker, el contenedor puede recibirlos pero el host los bloquea y la transferencia falla.

**¿Docker bypasea el firewall del sistema operativo (UFW)?**
Sí. Docker escribe directamente en las reglas de `iptables` con mayor prioridad que UFW. Aunque UFW esté activo y bloqueando un puerto, si Docker lo expone, será accesible desde fuera. Por esto no es necesario abrir los puertos manualmente en UFW para los servicios en Docker.

**¿Qué diferencia hay entre la IP interna del contenedor y la IP del host?**
El contenedor tiene su propia IP en la red interna de Docker (ej. `172.17.0.2`), asignada automáticamente por Docker. El host tiene la IP real de la red física (ej. `192.168.74.147`). Los clientes externos solo pueden llegar a la IP del host — Docker hace el puente entre ambas mediante NAT interno.

**¿Qué es la red `bridge` de Docker y cómo funciona?**
Es la red por defecto que Docker crea (`docker0`). Todos los contenedores se conectan a ella y pueden comunicarse entre sí por nombre (ej. `ffmpeg-publisher` puede llegar a `rtmp-nginx` usando el nombre `rtmp`). El host actúa como gateway de esta red interna hacia la red física.

**¿Cómo se comunican `ffmpeg-publisher` y `rtmp-nginx` internamente?**
Están en la misma red Docker, por lo que `ffmpeg-publisher` puede llegar a `rtmp-nginx` usando directamente el nombre del servicio `rtmp` como hostname: `rtmp://rtmp/live/${STREAM_KEY}`. Docker resuelve ese nombre a la IP interna del contenedor `rtmp-nginx` automáticamente.

**¿Por qué en RTMP se expone el puerto 1935 y en FTP el 21?**
Son los puertos estándar definidos por cada protocolo. RTMP usa 1935 por especificación del protocolo. FTP usa 21 para el canal de control. Usar los puertos estándar hace que los clientes (VLC, FileZilla, OBS) se conecten sin necesidad de configuración extra.

**¿Qué pasa si dos contenedores intentan usar el mismo puerto del host?**
Docker falla al levantar el segundo contenedor con el error `port is already allocated`. Por eso el servidor RTMP y el servidor Nginx web no pueden estar en la misma VM con el puerto 80 mapeado en ambos simultáneamente — uno de los dos tiene que usar un puerto diferente o estar en una VM distinta.
