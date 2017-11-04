#!/bin/bash

setup() {
    echo "Setting up testing environment.."

    mkdir -p bin 
    mkdir -p autorun

    # Symbolic link library to cwd
    ln -s ../websocket.lua ./websocket.lua

    # Symbolic link tests to autorun
    ln -s ./websocket.test.lua ./autorun/websocket.test.lua
    
    # Download bromsock
    echo "Downloading bromsock.."
    wget https://github.com/Bromvlieg/gm_bromsock/raw/master/Builds/gmsv_bromsock_linux_nossl_ubuntu.dll \
        -O bin/gmsv_bromsock_linux.dll
    echo "Download complete."

    echo "Setup complete."
}

run() {
    echo "Starting docker container."

    docker run  \
        -P      \
        -it     \
        --rm    \
        -v $(pwd):/gmod/garrysmod/addons/websocket/lua                 \
        -v $(pwd)/bin:/gmod/garrysmod/lua/bin                          \
        -v $(pwd)/autorun:/gmod/garrysmod/addons/websocket/lua/autorun \
        countmarvin/gmod-docker:latest 
}

if [ ! -f bin/gm_bromsock_linux.dll ]; then 
    setup
fi

run