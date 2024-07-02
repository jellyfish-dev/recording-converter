#!/usr/bin/env node

const yargs = require("yargs/yargs");
const { hideBin } = require("yargs/helpers");

import { startServer } from "./src/server";
import { runBenchmark } from "./src/benchmarkRtc";

const args = yargs(hideBin(process.argv))
  .option("fishjam-address", {
    type: "string",
    description: "Address of Fishjam server",
  })
  .options("fishjam-token", {
    type: "string",
    description: "Fishjam API token",
  })
  .option("secure", {
    type: "boolean",
    description: "Use secure connection (https / wss)",
    default: false,
  })
  .options("peers", {
    type: "integer",
    description: "Number of peers",
  })
  .options("peers-per-room", {
    type: "integer",
    description: "Number of peers in each room",
  })
  .option("active-peers", {
    type: "integer",
    default: undefined,
    decription:
      "Number of active peers in each room, default to `peers-per-room`",
  })
  .option("duration", {
    type: "integer",
    description: "Duration of the benchmark (s)",
    default: 60,
  })
  .option("peer-delay", {
    type: "integer",
    description: "Delay between joining of each peer (s)",
    default: 1,
  })
  .option("chrome-executable", {
    type: "string",
    description: "Path to Google Chrome executable",
  })
  .option("peers-per-browser", {
    type: "integer",
    description: "Number of peers spawned per browser",
    default: 1,
  })
  .option("csv-report-path", {
    type: "string",
    description: "Path used to save csv report",
    default: "./report.csv"
  })
  .option("use-simulcast", {
    type: "boolean",
    description: "If set to true simulcast will be enabled",
    default: false
  })
  .demandOption([
    "fishjam-address",
    "fishjam-token",
    "peers",
    "peers-per-room",
    "chrome-executable",
  ]).argv;

(async () => {
  args.targetEncoding = args.useSimulcast ? "h" : "m";
  args.availableEncodings = ["l", "m", "h"];

  // Start the frontend server
  startServer({
    fishjamAddress: args.fishjamAddress,
    secure: args.secure,
    targetEncoding: args.targetEncoding,
    activeEncodings: args.availableEncodings,
    useSimulcast: args.useSimulcast,
  });

  args.peersPerRoom = Math.min(args.peersPerRoom, args.peers);
  if (args.activePeers == undefined) args.activePeers = args.peersPerRoom;
  args.activePeers = Math.min(args.activePeers, args.peersPerRoom);
  console.log(args);

  runBenchmark(args);
})();
