import { VideoStatsSchema } from "./rtcMOS1.ts";
import { AudioStats, VideoStats } from "./rtcMOS1";
import { calculateVideoScore } from "./rtcMOS1";
import { FishjamClient } from "@fishjam-dev/ts-client";

export type VideoStatistics = VideoStats & { type: "video" };
export type AudioStatistics = AudioStats & { type: "audio" };
export type Statistics = VideoStatistics | AudioStatistics;
export type TrackIdentifier = string;

type InboundRtpId = string;
type Inbound = Record<InboundRtpId, any>;

let intervalId: NodeJS.Timer | null = null;
let data: Record<TrackIdentifier, Statistics> = {};

export const rtc_score_callback = (client: FishjamClient<PeerMetadata, TrackMetadata>) => {
  let prevTime: number = 0;
  let lastInbound: Inbound | null = null;

  intervalId = setInterval(async () => {
    if (!client) return;

    const currTime = Date.now();
    const dx = currTime - prevTime;

    if (!dx) return;

    const stats: RTCStatsReport = await client.getStatistics();
    const result: Record<string, any> = {};

    stats.forEach((report, id) => {
      result[id] = report;
    });

    const inbound: Inbound = getGroupedStats(result, "inbound-rtp");
    Object.entries(inbound).forEach(([id, report]) => {
      if (!lastInbound) return;
      if (report?.kind !== "video") return;

      const lastReport = lastInbound[id];

      const currentBytesReceived: number = report?.bytesReceived ?? 0;

      if (!currentBytesReceived) return;

      const prevBytesReceived: number = lastReport?.bytesReceived ?? 0;

      const bitrate = (8 * (currentBytesReceived - prevBytesReceived) * 1000) / dx; // bits per seconds

      const dxPacketsLost = (report?.packetsLost ?? 0) - (lastReport?.packetsLost ?? 0);
      const dxPacketsReceived = (report?.packetsReceived ?? 0) - (lastReport?.packetsReceived ?? 0);
      const packetLoss = dxPacketsReceived ? (dxPacketsLost / dxPacketsReceived) * 100 : NaN; // in %

      const selectedCandidatePairId = result[report?.transportId || ""]?.selectedCandidatePairId;
      const roundTripTime = result[selectedCandidatePairId]?.currentRoundTripTime;

      const dxJitterBufferEmittedCount =
        (report?.jitterBufferEmittedCount ?? 0) - (lastReport?.jitterBufferEmittedCount ?? 0);
      const dxJitterBufferDelay = (report?.jitterBufferDelay ?? 0) - (lastReport?.jitterBufferDelay ?? 0);
      const bufferDelay = dxJitterBufferEmittedCount > 0 ? dxJitterBufferDelay / dxJitterBufferEmittedCount : 0;

      const codecId = report?.codecId || "";

      const codec = result[codecId]?.mimeType?.split("/")?.[1];

      const videoStats = VideoStatsSchema.safeParse({
        bitrate,
        packetLoss,
        codec,
        bufferDelay,
        roundTripTime,
        frameRate: report?.framesPerSecond ?? NaN,
      });

      if (videoStats.success && report?.trackIdentifier) {
        const stats = { ...videoStats.data, type: "video" as const };
        data[report.trackIdentifier] = {
          ...data[report.trackIdentifier],
          ...stats,
        };
      }
    });

    const videoScores = generate_video_scores(data);
    console.log(`scores: ${JSON.stringify(videoScores)}`);

    lastInbound = inbound;
    prevTime = currTime;
  }, 1000);
};

const generate_video_scores = (data: Record<TrackIdentifier, Statistics>) => {
  const videoIds = Object.keys(data).filter((key: string) => data[key].type == "video");
  return videoIds.map((id) => {
    const videoStats = data[id] as VideoStatistics;
    return calculateVideoScore({
      codec: videoStats.codec,
      bitrate: videoStats.bitrate,
      bufferDelay: videoStats.bufferDelay,
      roundTripTime: videoStats.roundTripTime,
      frameRate: videoStats.frameRate,
      expectedWidth: 1280,
      expectedFrameRate: 24,
      expectedHeight: 720,
    });
  });
};

const getGroupedStats = (result: Record<string, any>, type: string) =>
  Object.entries(result)
    .filter(([_, value]) => value.type === type)
    .reduce((prev, [key, value]) => {
      prev[key] = value;
      return prev;
    }, {});
