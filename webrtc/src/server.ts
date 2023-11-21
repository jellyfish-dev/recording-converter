import { JellyfishConfig } from "./types";

const { createServer } = require("vite");

import { TrackEncoding } from "@jellyfish-dev/ts-client-sdk";

export const startServer = async ({
  jellyfishAddress,
  secure,
  targetEncoding,
  activeEncodings,
}: JellyfishConfig) => {
  const server = await createServer({
    configFile: false,
    root: "./frontend",
    server: {
      port: 5005,
    },
    define: {
      "process.env.JF_ADDR": JSON.stringify(jellyfishAddress),
      "process.env.JF_PROTOCOL": JSON.stringify(secure ? "wss" : "ws"),
      "process.env.TARGET_ENCODING": JSON.stringify(targetEncoding),
      "process.env.ACTIVE_ENCODINGS": JSON.stringify(activeEncodings.join("")),
    },
  });
  await server.listen();
};
