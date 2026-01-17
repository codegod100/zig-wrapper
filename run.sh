#!/bin/bash
set -e
rm -rf zig-cache .zig-cache
zig build -fno-emit-bin -fno-emit-asm -femit=llvm-bc
zig build
