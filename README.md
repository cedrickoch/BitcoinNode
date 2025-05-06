Commands to setup the bitcoin node

ssh to the node
cd /home/pi
git clone https://github.com/cedrickoch/BitcoinNode.git
cd BitcoinNode
wget https://lopp.net/download/utxo-snapshot-height-840000.dat?ref=blog.lopp.net
# Import the bitcoin snapshot from https://blog.lopp.net/bitcoin-node-sync-with-utxo-snapshots/
docker-compose -f docker-compose-import.yml up
# Start the applications
docker-compose up
