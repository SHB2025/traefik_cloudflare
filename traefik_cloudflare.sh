#!/bin/bash
set -e

if [[ "$EUID" -ne 0 ]]; then
  echo "Greška: Skripta zahtijeva root prava. Ponovno pokretanje sa sudo..."
  echo "Error: Script requires root. Restart with sudo..."
  exec sudo "$0" "$@"
fi

print_instructions() {
  printf "Koraci za generisanje CLOUDFLARE_API_TOKEN-a:\n"
  printf "1. Prijavite se na svoj Cloudflare račun.\n"
  printf "2. Idite na Profil.\n"
  printf "3. Kliknite na API tokeni sa lijeve strane.\n"
  printf "4. Kliknite na Kreiraj token.\n"
  printf "5. Odaberite predložak "Edit zone DNS".\n"
  printf "6. Dodijelite naziv tokenu i prava:\n"
  printf "   Permissions: Zone/DNS/Edit"
  printf "   Zone Resources: Include/Specific zone/select domain name"
  printf "7. Kliknite na Stvori token.\n"
  printf "8. Kopirajte tajnu tokena i sačuvajte je na sigurnom mjestu a zatim podesite na Cloaudflare prodilu domene Current encryption mode: Full (strict).\n"
  printf "#############################################"
  printf "Steps to generate a CLOUDFLARE_API_TOKEN:\n"
  printf "1. Log in to your Cloudflare account.\n"
  printf "2. Go to Profile.\n"
  printf "3. Click on API Tokens on the left.\n"
  printf "4. Click on Create Token.\n"
  printf "5. Select the "Edit zone DNS" template.\n"
  printf "6. Assign a name and permissions to the token:\n"
  printf " Permissions: Zone/DNS/Edit"
  printf " Zone Resources: Include/Specific zone/select domain name"
  printf "7. Click on Create Token.\n"
  printf "8. Copy the token secret and save it in a safe place and then set it to Cloudflare domain extension Current encryption mode: Full (strict).\n"
}

print_instructions

# Funkcija za siguran unos povjerljivih podataka sa prikazom zvjezdica
# Function for secure entry of confidential data with star display
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

secure_read "Unesite vaš Cloudflare API token (Enter your Cloudflare API token): " CLOUDFLARE_API_TOKEN
read -p "Unesite vašu Cloudflare email adresu (Enter your Cloudflare email address): " CLOUDFLARE_EMAIL
read -p "Unesite naziv poddomene za Traefik (Enter a subdomain name for Traefik): " DOMAIN_NAME
read -p "Unesite naziv emaila za Let's Encrypt (Enter your Let's Encrypt email name): " LETSENCRYPT_EMAIL
secure_read "Unesite korisničko ime za osnovnu autentifikaciju (Enter your username for basic authentication.): " AUTH_USER
secure_read "Unesite lozinku za osnovnu autentifikaciju (Enter a password for basic authentication): " AUTH_PASSWORD

for var in CLOUDFLARE_API_TOKEN CLOUDFLARE_EMAIL DOMAIN_NAME LETSENCRYPT_EMAIL AUTH_USER AUTH_PASSWORD; do
  if [[ -z "${!var}" ]]; then
    echo "Greška: Svi unosi su obavezni."
    echo "Error: All entries are required."
    exit 1
  fi
done

mkdir -p traefik

if ! command -v htpasswd &> /dev/null; then
  echo "htpasswd alat nije pronađen. Instalacija..."
  echo "htpasswd tool not found. Installing..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt-get update
    sudo apt-get install apache2-utils -y
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install httpd
  else
    echo "Greška: Nije podržana platforma za automatsku instalaciju htpasswd alata."
    echo "Error: Platform not supported for automatic installation of htpasswd tool."
    exit 1
  fi
fi

HASHED_USER=$(htpasswd -nb "$AUTH_USER" "$AUTH_PASSWORD")
echo "$HASHED_USER" > traefik/.traefikpasswd

if [[ ! -f "traefik/.traefikpasswd" ]]; then
  echo "Greška: .traefikpasswd fajl nije kreiran."
  echo "Error: .traefikpasswd file not created."
  exit 1
else
  echo "Fajl .traefikpasswd kreiran uspješno."
  echo "File .traefikpasswd created successfully."
fi

cat <<EOF > traefik/.env
CF_API_TOKEN="$CLOUDFLARE_API_TOKEN"
CF_API_EMAIL="$CLOUDFLARE_EMAIL"
DOMAIN_NAME="$DOMAIN_NAME"
LETSENCRYPT_EMAIL="$LETSENCRYPT_EMAIL"
HOST_NAME="$DOMAIN_NAME"
EOF

if [[ ! -f "traefik/.env" ]]; then
  echo "Greška: .env fajl nije kreiran."
  echo "Error: .env file not created."
  exit 1
else
  echo ".env fajl kreiran uspješno."
  echo ".env file created successfully."
fi

mkdir -p traefik/data/configurations traefik/certificates
echo "Direktoriji kreirani uspješno."
echo "Directories created successfully."

# Generisanje docker-compose.yml fajla koristeći heredoc
# Generating a docker-compose.yml file using heredoc
cat <<EOF > traefik/docker-compose.yml
networks:
  traefik:
    external: true
    name: traefik

services:
  traefik:
    container_name: traefik
    image: traefik:latest
    command:
      - --api=true
      - --api.dashboard=true
      - --certificatesresolvers.letsencrypt.acme.dnschallenge.delaybeforecheck=0
      - --certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.letsencrypt.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53
      - --certificatesresolvers.letsencrypt.acme.dnschallenge=true
      - --certificatesresolvers.letsencrypt.acme.email=\${CF_API_EMAIL}
      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
      - --entrypoints.http.address=:80
      - --entrypoints.https.address=:443
      - --entryPoints.https.http3
      - --entryPoints.https.http3.advertisedport=443
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.file.directory=/etc/traefik/dynamic
    env_file:
      - ./.env
    environment:
      - CLOUDFLARE_DNS_API_TOKEN=\${CF_API_TOKEN}
    hostname: \${HOST_NAME}
    labels:
      - traefik.enable=true
      - traefik.http.middlewares.auth.basicauth.usersfile=/etc/traefik/.traefikpasswd
      - traefik.http.middlewares.to-https.redirectscheme.scheme=https
      - traefik.http.routers.to-https.entrypoints=http
      - traefik.http.routers.to-https.middlewares=to-https
      - traefik.http.routers.to-https.rule=HostRegexp(\`{host:.+}\`)
      - traefik.http.routers.traefik.entrypoints=https
      - traefik.http.routers.traefik.middlewares=auth
      - traefik.http.routers.traefik.rule=Host(\`\${HOST_NAME}\`)
      - traefik.http.routers.traefik.service=api@internal
      - traefik.http.routers.traefik.tls.certresolver=letsencrypt
      - traefik.http.routers.traefik.tls=true
      - traefik.http.routers.dashboard.entrypoints=https
      - traefik.http.routers.dashboard.rule=Host(\`\${DOMAIN_NAME}\`)
      - traefik.http.routers.dashboard.service=api@internal
      - traefik.http.routers.dashboard.tls.certresolver=letsencrypt
      - traefik.http.routers.dashboard.tls=true
    networks:
      - traefik
    ports:
      - 80:80
      - 443:443/tcp
      - 443:443/udp
      - 8080:8080
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme:/letsencrypt
      - ./data:/etc/traefik/dynamic
      - ./.traefikpasswd:/etc/traefik/.traefikpasswd:ro
EOF

echo "docker-compose.yml fajl kreiran uspješno."
echo "docker-compose.yml file created successfully."

# Generisanje tls.yml fajla
# Generating the tls.yml file
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

echo "tls.yml fajl kreiran uspješno."
echo "tls.yml file created successfully."

if ! docker network inspect traefik >/dev/null 2>&1; then
  echo "Kreiranje Traefik mreže..."
  echo "Creating Traefik network..."
  docker network create traefik
  echo "Traefik mreža kreirana uspješno."
  echo "Traffic network created successfully."
else
  echo "Traefik mreža već postoji."
  echo "Traffic network already exists."
fi

read -p "Želite li automatski pokrenuti Traefik? (da/ne) / Do you want to start Traefik automatically? (yes=da/no=ne): " AUTOMATIC_START
if [ "$AUTOMATIC_START" == "da" ]; then
  echo "Pokrećem Traefik..."
  echo "Starting Traefik..."
  cd traefik
  docker-compose up -d || docker compose up -d
  echo "Traefik je uspješno pokrenut."
  echo "Traffic started successfully."
else
  echo "Traefik nije automatski pokrenut. Možete ga ručno pokrenuti sa 'docker-compose up -d' ili 'docker compose up -d' u direktoriju 'traefik'."
  echo "Traefik is not started automatically. You can start it manually with 'docker-compose up -d' or 'docker compose up -d' in the 'traefik' directory."
fi
