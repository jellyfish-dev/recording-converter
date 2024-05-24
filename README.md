# Recording Converter

[![codecov](https://codecov.io/gh/fishjam-dev/recording-converter/branch/main/graph/badge.svg?token=ANWFKV2EDP)](https://codecov.io/gh/fishjam-dev/recording-converter)
[![CircleCI](https://circleci.com/gh/fishjam-dev/recording-converter.svg?style=svg)](https://circleci.com/gh/fishjam-dev/recording-converter)

Recording Converter is a docker image that allows to convert recording created with the use of [RecordingComponent](https://fishjam-dev.github.io/fishjam-docs/next/getting_started/components/recording) in Fishjam to HLS.

The environment variables possible to pass are:
* `AWS_S3_ACCESS_KEY_ID` - access key ID to S3 bucket
* `AWS_S3_SECRET_ACCESS_KEY` - secret access key to S3 bucket
* `AWS_S3_REGION` - a region on which the bucket is stored
* `BUCKET_NAME` - name of the bucket
* `REPORT_PATH` - path to `report.json` on the S3 bucket
* `OUTPUT_DIRECTORY_PATH` - output path in S3 bucket, it can be absolute or relative to the path of the report

### Example
In the example directory there is `script.sh` that allows to build a docker image from sources and run it with envs provided in `.env` file.

The `upload_directory.exs` file provides a bunch of functions that allow to upload, list and delete files on S3 bucket.

## Copyright and License

Copyright 2024, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
