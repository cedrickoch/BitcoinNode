#!/bin/sh

LOGFILE=/data/.bitcoin/debug.log
SEARCH_TEXT="00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048"

echo "Import starting"
bitcoind -daemon -printtoconsole -rpcbind=0.0.0.0 -rpcallowip=0.0.0.0/0 -datadir=/data/.bitcoin

# Wait for the block headers to be downloaded
while true; do
    # Check if the text appears in the log file
    if grep -q "$SEARCH_TEXT" "$LOGFILE"; then
        echo "Block headers downloaded"
        break
    fi
    
    # Wait for a moment before checking again
    sleep 5
    echo "Waiting for block headers to be downloaded..."
done

echo "Block headers downloaded, starting import"
bitcoin-cli -datadir=/data/.bitcoin -rpcclienttimeout=3600 loadtxoutset /utxo-snapshot-height-840000.dat
echo "Import completed"
