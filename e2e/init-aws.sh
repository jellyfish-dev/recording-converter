#!/bin/bash

BUCKET_NAME=bucket
awslocal s3 mb s3://$BUCKET_NAME
awslocal s3 cp --recursive $DIRECTORY_PATH s3://$BUCKET_NAME/$TEST_NAME/
