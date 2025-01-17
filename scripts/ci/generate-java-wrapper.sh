#!/usr/bin/env sh

# Exit on error (with shell)
set -e

. $HOME/.web3j/source.sh

# Generate Java wrappers
for abi_file in ./android/abi/*; do
    bin_file="./android/bin/$(basename $abi_file .abi).bin"

    web3j generate solidity \
        --abiFile="$abi_file" \
        --binFile="$bin_file" \
        -o ./scripts/java/src/main/java \
        -p network.lukso.lsp.smartcontracts
done

# Build jar
cd scripts/java
chmod +x build.gradle
gradle build