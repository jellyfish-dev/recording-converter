#!/bin/bash

response=$(curl -s http://localhost:4566/_localstack/init)

if echo $response | grep -q "SUCCESSFUL"; then
  exit 0
else
  exit 1
fi
