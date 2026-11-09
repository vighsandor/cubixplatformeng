#!/usr/bin/env bash
# A sbx környezet lebontása – lásd kornyezet-lebontas.sh
exec "$(dirname "$0")/kornyezet-lebontas.sh" sbx "$@"
