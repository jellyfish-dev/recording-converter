import { chromium, Browser } from "playwright";
import { TrackEncoding } from "@fishjam-dev/ts-client";
import { Client } from "./client";
import { Args } from "./types";
import { getEncodingsReport, onEncodingsUpdate } from "./encodingReporter";

const frontendAddress = "http://localhost:5005";
const fakeVideo = "media/sample_video.mjpeg";
const fakeAudio = "media/sample_audio.wav";

const encodingReportPeriod = 5;
const encodingBitrate = new Map<TrackEncoding, number>([
  ["l", 0.15],
  ["m", 0.5],
  ["h", 1.5],
]);

const second = 1000;
const delay = (n: number) => {
  return new Promise((resolve) => setTimeout(resolve, n * second));
};

export const runBenchmark = async (args: Args) => {
  const client = new Client(args);
  await client.purge();

  const browsers = await addPeers(args);

  console.log("Started all browsers, running benchmark");

  for (
    let time = 0, step = encodingReportPeriod;
    time < args.duration;
    step = Math.min(step, args.duration - time), time += step
  ) {
    const report = getEncodingsReport();

    writeInPlace(
      `${time} / ${args.duration}s, Encodings: ${report.toString()}}`,
    );
    await delay(step);
  }

  writeInPlace(`${args.duration} / ${args.duration}s`);

  await cleanup(client, browsers);

  console.log("\nBenchmark finished, closing");
  process.exit(0);
};

const addPeers = async (args: Args) => {
  const client = new Client(args);

  let roomCount = 0;
  let peersAdded = 0;
  let peersInCurrentBrowser = 0;
  let browsers: Array<Browser> = [];
  let currentBrowser = await spawnBrowser(args.chromeExecutable);

  const { incomingBandwidth, outgoingBandwidth } = getEstimatedBandwidth(args);

  while (peersAdded < args.peers) {
    const response = await client.createRoom(
      `room${String(roomCount).padStart(2, "0")}`,
    );
    roomCount++;

    for (let j = 0; j < args.peersPerRoom && peersAdded < args.peers; j++) {
      await startPeer({
        browser: currentBrowser!,
        client: client,
        roomId: response.room.id,
        active: j < args.activePeers,
      });
      peersAdded++, peersInCurrentBrowser++;

      writeInPlace(
        `Browsers launched: ${peersAdded} / ${
          args.peers
        }  Expected network usage: Incoming/Outgoing ${incomingBandwidth}/${outgoingBandwidth} Mbps/s,  ${
          incomingBandwidth / 8
        }/${outgoingBandwidth / 8} MBps/s`,
      );
      await delay(args.peerDelay);

      if (peersInCurrentBrowser == args.peersPerBrowser) {
        browsers.push(currentBrowser!);
        currentBrowser = await spawnBrowser(args.chromeExecutable);
        peersInCurrentBrowser = 0;
      }
    }
  }
  console.log("");

  return browsers;
};

const spawnBrowser = async (chromeExecutable: string) => {
  const browser = await chromium.launch({
    args: [
      "--use-fake-device-for-media-stream",
      `--use-file-for-fake-video-capture=${fakeVideo}`,
      `--use-file-for-fake-audio-capture=${fakeAudio}`,
      "--auto-accept-camera-and-microphone-capture",
      "--no-sandbox",
    ],

    // Start headfull browser
    // devtools: true,
    logger: {
      isEnabled: (name: any, severity: any) => name === "browser",
      log: (name: any, severity: any, message: any, args: any) =>
        console.log(`${name} ${message}`),
    },
    executablePath: chromeExecutable,
  });

  return browser;
};

const startPeer = async ({
  browser,
  client,
  roomId,
  active,
}: {
  browser: Browser;
  client: Client;
  roomId: string;
  active: boolean;
}) => {
  const peerToken = (await client.addPeer(roomId)).token;

  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto(
    `${frontendAddress}?peerToken=${peerToken}&activePeer=${JSON.stringify(
      active,
    )}`,
  );
  page.on("console", (msg) => onEncodingsUpdate(msg, peerToken));
};

const cleanup = async (client: Client, browsers: Array<Browser>) => {
  browsers.forEach((browser) => browser.close());
  await client.purge();
};

const getEstimatedBandwidth = (args: Args) => {
  const maxPeersInRoom = Math.min(args.peers, args.peersPerRoom);
  const fullRooms = Math.floor(args.peers / maxPeersInRoom);
  const peersInLastRoom = args.peers % args.peersPerRoom;
  const activePeersInLastRoom = Math.min(args.activePeers, peersInLastRoom);

  const incomingTracks = fullRooms * args.activePeers + activePeersInLastRoom;

  const outgoingTracks =
    fullRooms * args.activePeers * (maxPeersInRoom - 1) +
    activePeersInLastRoom * (peersInLastRoom - 1);

  const outgoingBandwidth =
    encodingBitrate.get(args.targetEncoding)! * outgoingTracks;

  let incomingBandwidth = args.availableEncodings.reduce(
    (acc, encoding) => acc + encodingBitrate.get(encoding)! * incomingTracks,
    0,
  );

  return { incomingBandwidth, outgoingBandwidth };
};

const writeInPlace = (text: string) => {
  process.stdout.clearLine(0);
  process.stdout.cursorTo(0);
  process.stdout.write(text);
};
