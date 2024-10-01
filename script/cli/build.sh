#!/bin/bash

mkdir -p ./src/assets
wget -O ./src/assets/chains.json https://chainid.network/chains.json

cargo build --release

rm ./src/assets/chains.json

cp ./target/release/deploy-cli ../../deploy-cli