#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Werror Core/SoulCore.cpp Tests/core_tests.cpp -o .build/core-tests
.build/core-tests
