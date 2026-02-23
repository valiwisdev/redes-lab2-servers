# Nginx + Docker (HTTP y HTTPS) en Ubuntu

Servidor Nginx en Docker con:

- **HTTP** → puerto `80`
- **HTTPS** → puerto `443` (certificado SSL autofirmado con OpenSSL)

---

## Archivos del repo

```bash
.
├── docker-compose.yml
├── nginx.conf
├── html/
│   └── index.html
├── .gitignore
└── README.md
```

## Obtener Hostname
```bash
hostname -I
```

## Comandos

### Crear Certificado
```bash
mkdir -p certs

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout certs/server.key \
  -out certs/server.crt \
  -days 365 \
  -subj "/CN=YOUR_DOMAIN_OR_IP"

chmod 600 certs/server.key
```

### Iniciar el servidor
```bash
docker-compose up -d
```