#/bin/bash

SCRIPT_DIR=$(dirname $0)

IMAGE_NAME="recording-converter-example-x86"

docker buildx create --name mybuilder
docker buildx use mybuilder
docker buildx inspect --bootstrap

ARG CACHEBUST=1

docker buildx build --platform linux/amd64 --no-cache --build-arg CACHEBUST=$(date +%s) -t $IMAGE_NAME .

docker run -it --env-file=$SCRIPT_DIR/../.env --rm -v $SCRIPT_DIR/output:/app/output $IMAGE_NAME
