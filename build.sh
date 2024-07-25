#!/bin/bash 

forge clean;
repos=$(ls src/pkgs/);
for repo in $repos
do
    echo "Starting build of $repo";
    FOUNDRY_PROFILE=$repo forge build;
done
