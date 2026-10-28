#!/bin/bash
# 兼容旧用法：等同于 ./setup.sh
exec "$(dirname "$0")/setup.sh" "$@"
