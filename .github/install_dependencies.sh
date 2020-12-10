#!/usr/bin/env bash

set -x

echo "Setting the environment to use ${DB} database"

BUNDLE_CONFIG=.bundle/config
mkdir -p $(dirname $BUNDLE_CONFIG)
cat <<EOF > $BUNDLE_CONFIG
---
BUNDLE_WITHOUT: pry:mysql:postgresql:concurrent_ruby_ext
EOF

case $DB in
    mysql)
        sed -i 's/:mysql//'g $BUNDLE_CONFIG
    ;;
    postgresql)
        sed -i 's/:postgresql//'g $BUNDLE_CONFIG
    ;;
    sqlite3)
        # the tests are by default using sqlite3: do nothing
    ;;
    *)
    echo "Unsupported database ${DB}"
    exit 1
    ;;
esac

if [ "$CONCURRENT_RUBY_EXT" = "true" ]; then
  echo "Enabling concurrent-ruby-ext"
  sed -i 's/:concurrent_ruby_ext//'g $BUNDLE_CONFIG
fi
gem update bundler
bundle install
