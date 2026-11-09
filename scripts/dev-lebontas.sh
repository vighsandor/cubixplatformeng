#!/usr/bin/env bash
# A dev környezet lebontása – lásd kornyezet-lebontas.sh
exec "$(dirname "$0")/kornyezet-lebontas.sh" dev "$@"
