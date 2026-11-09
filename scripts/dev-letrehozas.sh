#!/usr/bin/env bash
# A dev környezet létrehozása – lásd kornyezet-letrehozas.sh
exec "$(dirname "$0")/kornyezet-letrehozas.sh" dev "$@"
