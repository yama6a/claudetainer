#!/usr/bin/env bash
# Compiles one PHP version with mise in an image build stage. Xdebug and PCOV are built but stay unloaded.
set -euo pipefail

version="${1:?usage: php-install.sh <php> <xdebug> <pcov>}"
xdebug="${2:?}"
pcov="${3:?}"

export MISE_CACHE_DIR=/tmp/mise
# vfox-php only adds pdo_pgsql and zip on Linux. These cover the rest of the headers the base stage installs.
export PHP_EXTRA_CONFIGURE_OPTIONS="--with-bz2 --with-gmp --with-sodium --with-jpeg --with-webp --with-freetype"
mise install "php@$version"
prefix="$(mise where "php@$version")"

# The image ships one pinned Composer. vfox-php installs whatever is newest.
rm -f "$prefix/bin/composer"

for ext in "xdebug-$xdebug" "pcov-$pcov"; do
  curl -fsSL "https://pecl.php.net/get/$ext.tgz" | tar -xz -C /tmp "$ext"
  (
    cd "/tmp/$ext"
    "$prefix/bin/phpize"
    ./configure --with-php-config="$prefix/bin/php-config"
    make -j"$(nproc)"
    make install
  )
done

rm -rf /tmp/*
