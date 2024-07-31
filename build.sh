#!/bin/bash 
git submodule update --init --recursive --depth 1
forge clean;
repos=$(ls src/pkgs/);
for repo in $repos
do
    echo "Starting build of $repo";
    FOUNDRY_PROFILE=$repo forge build;
done
