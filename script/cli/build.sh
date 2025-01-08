#!/bin/bash

cargo build --release

cp ./target/release/deploy-cli ../../deploy-cli