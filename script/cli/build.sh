#!/bin/bash

mkdir -p ./src/assets
wget -O ./src/assets/chains.json https://chainid.network/chains.json

cargo build --release

cp ./target/release/deploy-cli ../../deploy-cli