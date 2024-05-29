# Fishjam Grinder WebRTC

Utility for running WebRTC stress-tests against [Fishjam Media Server](https://github.com/fishjam-dev/fishjam).

## Installation

Make sure to have installed [Node](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm) first.

Run `npm run setup`.

Ensure Chrome installation:
`npm run install-chrome`
The installation directory will vary, depending on the OS.

Generate latest Jellyfish Server SDK client:
`npx @openapitools/openapi-generator-cli generate -i https://raw.githubusercontent.com/fishjam-dev/fishjam/main/openapi.yaml -g typescript-axios -o ./server-sdk`

## Usage

Run `npm run grind -- --help` for usage information.

## Copyright and License

Copyright 2023, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
