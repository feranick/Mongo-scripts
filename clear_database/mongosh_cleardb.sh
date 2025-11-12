#!/bin/bash

if [ -z "$1" ]; then
    echo "ERROR: Missing required argument."
    echo "Usage: $0 <device_name>"
    exit 1
fi

MONGO_HOST="localhost:27017"
ADMIN_USER="admin"
ADMIN_PASS="password"
AUTH_DB="admin"

JS_SCRIPT="./mongosh_cleardb.js"

echo "Attempting to connect to MongoDB as user: $ADMIN_USER"

# Line 1: The backslash must be the ABSOLUTE LAST character on the line
mongosh "mongodb://${MONGO_HOST}/LabMonitorDB?authSource=${AUTH_DB}" \
  -u "$ADMIN_USER" \
  -p "$ADMIN_PASS" \
  --eval "var deviceArg = \"$1\";" \
  --file "$JS_SCRIPT"

if [ $? -eq 0 ]; then
    echo "MongoDB script executed successfully."
else
    echo "Error executing MongoDB script."
fi
