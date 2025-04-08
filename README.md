🛠️ Automatska Traefik + Cloudflare + Let's Encrypt Instalacija

📥 Kako preuzeti i pokrenuti skriptu / How to download and run the script
####################
## VAZNO: Za ispravno funkcionisanje skripta mora biti pokrenuta u korisničkom (user) folderu. Npr. /home/korisnik1/traefik_cloudflare.sh
## IMPORTANT: For proper functioning, the script must be run in the user folder. E.g. /home/user1/traefik_cloudflare.sh
####################
wget https://raw.githubusercontent.com/SHB2025/traefik_cloudflare/refs/heads/main/traefik_cloudflare.sh
chmod +x traefik_cloudflare.sh
sudo ./traefik_cloudflare.sh

🚀 Automatizirana bash skripta za brzo postavljanje sigurnog Traefik reverse proxy-ja
🇧🇦 Opis (Bosanski):

Ova bash skripta omogućava jednostavno i automatizirano postavljanje Traefik reverse proxy-ja sa sljedećim funkcionalnostima:

Integracija sa Cloudflare DNS API (uz vaš CLOUDFLARE_API_TOKEN)

Potpuno automatsko izdavanje SSL certifikata putem Let's Encrypt i Cloudflare proxy

HTTP/3 podrška, automatski redirect sa HTTP na HTTPS

Zaštićeni pristup Traefik dashboardu putem osnovne autentifikacije (Basic Auth)

Automatsko kreiranje .env, .traefikpasswd, docker-compose.yml i tls.yml fajlova

Osigurana konfiguracija sa opcijama kao što su HSTS, Rate limiting, Gzip kompresija (opcionalno)

🧩 Pogodno za:
Samostalne servere (npr. Hetzner, DigitalOcean, Proxmox VM)

One koji koriste Cloudflare kao DNS provider

Razvojne i produkcijske okoline

🇬🇧 Description (English):
This bash script allows you to quickly and securely set up a Traefik reverse proxy with:

Full Cloudflare DNS API support via CLOUDFLARE_API_TOKEN

Automated Let's Encrypt SSL certificate generation

HTTP/3 support, HTTP to HTTPS redirect

Secured access to Traefik dashboard using Basic Auth

Automatic generation of .env, .traefikpasswd, docker-compose.yml, and tls.yml

Hardened security config with options like HSTS, rate limiting, gzip compression (optional)

🧩 Perfect for:
Self-hosted environments (Hetzner, DigitalOcean, Proxmox VMs, etc.)

Users utilizing Cloudflare DNS

Both dev and production use cases
