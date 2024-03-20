#/bin/bash

SCRIPT_DIR=$(dirname $0)

# docker build --no-cache -t "recording-converter-example" .
docker build -t "recording-converter-example" .

docker run -it --env-file=$SCRIPT_DIR/../.env --rm -v $SCRIPT_DIR/output:/app/output recording-converter-example
