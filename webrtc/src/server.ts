import { FishjamConfig } from "./types";

const { createServer } = require("vite");

import { TrackEncoding } from "@fishjam-dev/ts-client";

export const startServer = async ({
  fishjamAddress,
  secure,
  targetEncoding,
  activeEncodings,
}: FishjamConfig) => {
  const server = await createServer({
    configFile: false,
    root: "./frontend",
    server: {
      port: 5005,
    },
    define: {
      "process.env.JF_ADDR": JSON.stringify(fishjamAddress),
      "process.env.JF_PROTOCOL": JSON.stringify(secure ? "wss" : "ws"),
      "process.env.TARGET_ENCODING": JSON.stringify(targetEncoding),
      "process.env.ACTIVE_ENCODINGS": JSON.stringify(activeEncodings.join("")),
    },
  });
  await server.listen();
};
