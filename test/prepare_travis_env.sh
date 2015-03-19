#!/usr/bin/env bash

echo "Setting the environment to use ${DB} database"

BUNDLE_CONFIG=.bundle/config
mkdir -p $(dirname $BUNDLE_CONFIG)
cat <<EOF > $BUNDLE_CONFIG
---
BUNDLE_WITHOUT: pry:mysql:postgresql
EOF

case $DB in
    mysql)
        sed -i 's/:mysql//'g $BUNDLE_CONFIG
        mysql -e 'create database travis_ci_test;'
        export DB_CONN_STRING='mysql2://root@localhost/travis_ci_test'
    ;;
    postgresql)
        sed -i 's/:postgresql//'g $BUNDLE_CONFIG
        psql -c 'create database travis_ci_test;' -U postgres
        export DB_CONN_STRING='postgres://postgres@localhost/travis_ci_test'
    ;;
    sqlite3)
        # the tests are by default using sqlite3: do nothing
    ;;
    *)
    echo "Unsupported database ${DB}"
    exit 1
    ;;
esac

bundle install
