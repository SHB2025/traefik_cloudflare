#!/bin/bash
set -e

# Check if script is run as root, otherwise restart with sudo
# Provjerava da li je skripta pokrenuta kao root, u suprotnom se restartuje sa sudo
if [[ "$EUID" -ne 0 ]]; then
  echo "Error: Script requires root privileges. Restarting with sudo..."
  echo "Greška: Skripta zahtijeva root privilegije. Ponovno pokretanje sa sudo..."
  exec sudo "$0" "$@"
fi

# Function to print instructions for creating Cloudflare API Token
# Funkcija za ispis uputa kako kreirati Cloudflare API token
print_instructions() {
  printf "Steps to generate CLOUDFLARE_API_TOKEN:\n"
  printf "1. Log in to your Cloudflare account.\n"
  printf "2. Go to Profile.\n"
  printf "3. Click on API Tokens on the left.\n"
  printf "4. Click Create Token.\n"
  printf "5. Choose a template or create a custom token.\n"
  printf "6. Assign permissions:\n"
  printf "   - Zone: Read\n"
  printf "   - DNS: Edit\n"
  printf "   - SSL/TLS: Read\n"
  printf "7. Click Create Token and save it in a secure location.\n"
  printf "_______________________________________________________"
  printf "Koraci za generiranje CLOUDFLARE_API_TOKEN:\n"
  printf "1. Prijavite se na svoj Cloudflare račun.\n"
  printf "2. Idi na profil.\n"
  printf "3. Kliknite na API tokene na lijevoj strani.\n"
  printf "4. Kliknite Kreiraj token.\n"
  printf "5. Odaberite predložak ili kreirajte prilagođeni token.\n"
  printf "6. Dodijeli dozvole:\n"
  printf " - Zona: Čitanje\n"
  printf " - DNS: Uredi\n"
  printf " - SSL/TLS: Čitaj\n"
  printf "7. Kliknite Kreiraj token i spremite ga na sigurnu lokaciju.\n"
  
}

print_instructions

# Function for secure input of sensitive data
# Funkcija za siguran unos osjetljivih podataka
secure_read() {
  local prompt="$1"
  local var_name="$2"
  local input=""

  echo -n "$prompt"
  while IFS= read -r -s -n 1 char; do
    if [[ $char == $'\0' ]]; then
      break
    fi
    if [[ $char == $'\177' ]]; then
      if [[ -n $input ]]; then
        input="${input%?}"
        printf '\b \b'
      fi
    else
      input+="$char"
      printf '*'
    fi
  done
  echo
  eval "$var_name='$input'"
}

# User input
# Unos korisničkih podataka
secure_read "Enter your Cloudflare API token/Unesite svoj Cloudflare API token: " CLOUDFLARE_API_TOKEN
read -p "Enter your Cloudflare email address/Unesite svoju Cloudflare adresu e-pošte: " CLOUDFLARE_EMAIL
read -p "Enter your subdomain name for Traefik/Unesite ime vaše poddomene za Traefik: " DOMAIN_NAME
secure_read "Enter username for Traefik Dashboard basic authentication/Unesite korisničko ime za osnovnu autentifikaciju Traefik Dashboard: " AUTH_USER
secure_read "Enter password for Traefik Dashboard basic authentication/Unesite lozinku za osnovnu autentifikaciju Traefik Dashboard: " AUTH_PASSWORD

# Check if all variables are provided
# Provjerava da li su svi podaci uneseni
for var in CLOUDFLARE_API_TOKEN CLOUDFLARE_EMAIL DOMAIN_NAME AUTH_USER AUTH_PASSWORD; do
  if [[ -z "${!var}" ]]; then
    echo "Error: All inputs are required."
    echo "Greška: svi ulazni podatci su potrebni."
    exit 1
  fi
done

# Create necessary directories and files
# Kreira potrebne direktorije i fajlove
mkdir -p traefik/data/configurations traefik/letsencrypt
touch traefik/letsencrypt/acme.json
chmod 600 traefik/letsencrypt/acme.json

echo "acme.json file created with correct permissions."
echo "acme.json fajl kreiran sa ispravnim dozvolama."

# Install htpasswd tool if not present
# Instalira htpasswd alat ako nije prisutan
if ! command -v htpasswd &> /dev/null; then
  echo "htpasswd tool not found. Installing..."
  echo "htpasswd alat nije pronađen. Instaliranje..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt-get update
    sudo apt-get install apache2-utils -y
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install httpd
  else
    echo "Error: Unsupported platform for automatic htpasswd installation."
    echo "Greška: Nepodržana platforma za automatsku instalaciju htpasswd."
    exit 1
  fi
fi

# Generate hashed password and write to file
# Generiše hashiranu lozinku i zapisuje u fajl
HASHED_USER=$(htpasswd -nb "$AUTH_USER" "$AUTH_PASSWORD")
echo "$HASHED_USER" > traefik/.traefikpasswd

if [[ ! -f "traefik/.traefikpasswd" ]]; then
  echo "Error: .traefikpasswd file was not created."
  echo "Greška: .traefikpasswd datoteka nije kreirana."
  exit 1
else
  echo ".traefikpasswd file created successfully."
  echo ".traefikpasswd datoteka uspješno kreirana."
fi

# Write environment variables to .env file
# Zapisuje varijable okruženja u .env fajl
cat <<EOF > traefik/.env
CF_API_TOKEN="$CLOUDFLARE_API_TOKEN"
CF_API_EMAIL="$CLOUDFLARE_EMAIL"
DOMAIN_NAME="$DOMAIN_NAME"
EOF

if [[ ! -f "traefik/.env" ]]; then
  echo "Error: .env file was not created."
  exit 1
else
  echo ".env file created successfully."
fi

# Generate docker-compose.yml for Traefik
# Generiše docker-compose.yml za Traefik
cat <<EOF > traefik/docker-compose.yml
networks:
  traefik:
    external: true
    name: traefik

services:
  traefik:
    container_name: traefik
    image: traefik:v3.3.3
    restart: unless-stopped

    command:
      - --api.dashboard=true
      - --log.level=INFO
      - --entrypoints.http.address=:80
      - --entrypoints.https.address=:443
      - --entrypoints.https.http.tls=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.file.directory=/etc/traefik/dynamic
      - --certificatesresolvers.cloudflare.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.cloudflare.acme.dnschallenge.delaybeforecheck=0

    env_file:
      - ./.env

    environment:
      - CLOUDFLARE_DNS_API_TOKEN=\${CF_API_TOKEN}
    hostname: \${DOMAIN_NAME}

    ports:
      - 80:80
      - 443:443/tcp
      - 443:443/udp

    networks:
      - traefik

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
      - ./data:/etc/traefik/dynamic
      - ./.traefikpasswd:/etc/traefik/.traefikpasswd:ro

    labels:
      - traefik.enable=true

      # Basic Auth Middleware
      # Middleware za osnovnu autentifikaciju
      - traefik.http.middlewares.auth.basicauth.usersfile=/etc/traefik/.traefikpasswd
      - traefik.http.middlewares.auth.basicauth.removeheader=true

      # Redirect HTTP to HTTPS
      # Redirekcija HTTP ka HTTPS
      - traefik.http.middlewares.to-https.redirectscheme.scheme=https
      - traefik.http.routers.to-https.entrypoints=http
      - traefik.http.routers.to-https.middlewares=to-https
      - traefik.http.routers.to-https.rule=HostRegexp(\`{host:.+}\`)

      # Traefik Dashboard
      # Traefik kontrolna tabla
      - traefik.http.routers.traefik.entrypoints=https
      - traefik.http.routers.traefik.middlewares=auth
      - traefik.http.routers.traefik.rule=Host(\`\${DOMAIN_NAME}\`)
      - traefik.http.routers.traefik.service=api@internal
      - traefik.http.routers.traefik.tls.certresolver=cloudflare
      - traefik.http.routers.traefik.tls=true

      # Dashboard Router
      # Ruter za dashboard
      - traefik.http.routers.dashboard.entrypoints=https
      - traefik.http.routers.dashboard.rule=Host(\`\${DOMAIN_NAME}\`)
      - traefik.http.routers.dashboard.service=api@internal
      - traefik.http.routers.dashboard.tls.certresolver=cloudflare
      - traefik.http.routers.dashboard.tls=true
      - traefik.http.routers.dashboard.middlewares=auth
EOF

echo "docker-compose.yml for Traefik created successfully."
echo "docker-compose.yml za Traefik uspješno kreiran."

# Generate tls.yml file with TLS security settings
# Generiše tls.yml fajl sa TLS sigurnosnim postavkama
cat <<EOF > traefik/data/configurations/tls.yml
tls:
  options:
    tlsoptions:
      minVersion: VersionTLS12
      sniStrict: true
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
      alpnProtocols:
        - h2
        - http/1.1
        - h3
EOF

echo "tls.yml file created successfully."
echo "tls.yml fajl uspješno kreiran."

# Create docker network for Traefik if it doesn't exist
# Kreira docker mrežu za Traefik ako ne postoji
if ! docker network inspect traefik >/dev/null 2>&1; then
  echo "Creating Traefik network..."
  echo "Kreiranje Traefik mreže..."
  docker network create traefik
  echo "Traefik network created successfully."
  echo "Traefik mreža uspješno kreirana."
else
  echo "Traefik network already exists."
  echo "Traefik mreža već postoji."
fi

# Ask user if Traefik should be started automatically
# Pita korisnika da li želi automatski pokrenuti Traefik
read -p "Do you want to automatically start Traefik? (Y/N)/Želite li automatski pokrenuti Traefik? (Y/N): " AUTOMATIC_START
if [[ "$AUTOMATIC_START" == "y" || "$AUTOMATIC_START" == "Y" ]]; then
  echo "Starting Traefik..."
  echo "Početak Traefik..."
  cd traefik
  docker-compose up -d || docker compose up -d
  echo "Traefik started successfully."
  echo "Traefik je uspješno pokrenut."
else
  echo "Traefik was not started. You can start it manually with 'docker-compose up -d' or 'docker compose up -d' from the 'traefik' directory."
  echo "Traefik nije pokrenut. Možete ga pokrenuti ručno sa 'docker-compose up -d' ili 'docker compose up -d' iz 'traefik' direktorija."
fi
