#! /bin/sh

MARKER_FILE="/var/tmp/prerequisites_installed"

if [ ! -f "$MARKER_FILE" ]; then
    echo "Installing prerequisites..."
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get install docker -y
    sudo apt-get install docker-compose -y
    sudo usermod -aG docker pi

    # Create a marker file to indicate prerequisites are installed
    sudo touch "$MARKER_FILE"
    echo "Prerequisites installed. Rebooting..."
    sudo reboot
else
    echo "Prerequisites already installed. Proceeding to the next steps..."
    # Add your next steps here
    echo "Downloading bitcoin chain snapshot..."
    curl https://www.lopp.net/download/utxo-snapshot-height-840000.dat?ref=blog.lopp.net --output utxo-snapshot-height-840000.dat
    echo "Importing bitcoin chain snapshot..."
    docker-compose -f docker-compose-import.yml up
fi