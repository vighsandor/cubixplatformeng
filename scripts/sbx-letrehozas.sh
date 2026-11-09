#!/usr/bin/env bash
# A sbx környezet létrehozása – lásd kornyezet-letrehozas.sh
exec "$(dirname "$0")/kornyezet-letrehozas.sh" sbx "$@"
