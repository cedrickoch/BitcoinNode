#! /bin/sh

MARKER_FILE="/var/tmp/prerequisites_installed"

if [ ! -f "$MARKER_FILE" ]; then
    echo "Installing prerequisites..."
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get install docker -y
    # compose v2 plugin is preferred; the legacy binary is a fallback for hosts
    # where only the docker-compose package is available (see the shim below)
    sudo apt-get install docker-compose -y
    sudo usermod -aG docker pi

    # Create a marker file to indicate prerequisites are installed
    sudo touch "$MARKER_FILE"
    echo "Prerequisites installed. Rebooting..."
    sudo reboot
else
    echo "Prerequisites already installed. Proceeding to the next steps..."

    # The README uses `docker compose`; fall back to the legacy binary only if
    # compose v2 is genuinely unavailable, so both paths stay valid.
    if docker compose version >/dev/null 2>&1; then
        COMPOSE="docker compose"
    else
        COMPOSE="docker-compose"
        echo "compose v2 not available, falling back to docker-compose" >&2
    fi

    echo "Downloading bitcoin chain snapshot..."
    curl https://www.lopp.net/download/utxo-snapshot-height-840000.dat?ref=blog.lopp.net --output utxo-snapshot-height-840000.dat
    echo "Importing bitcoin chain snapshot..."
    $COMPOSE -f docker-compose-import.yml up
fi
