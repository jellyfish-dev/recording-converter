import { ConsoleMessage } from "playwright";
import { PeerToken, RawTrackEncodings } from "./types";

let rawTrackEncodings: RawTrackEncodings = new Map();

export class EncodingsReport {
  report: {
    l: number;
    m: number;
    h: number;
  };

  constructor(reportRaw: Map<string, string>) {
    const totalEncodings = { l: 0, m: 0, h: 0 };

    reportRaw.forEach((encodings: string, peerId: string) => {
      for (const layer_char of "lmh") {
        const layer = layer_char as "l" | "m" | "h";
        // RegEx that matches all occurences of `layer` in `encodings`
        const regex = new RegExp(layer, "g");
        totalEncodings[layer] += (encodings.match(regex) || []).length;
      }
    });

    this.report = totalEncodings;
  }

  toString = () => {
    return `l: ${this.report.l}, m: ${this.report.m}, h: ${this.report.h}`;
  };

  toJson = () => {
    return this.report;
  };
}

export const getEncodingsReport = () => {
  return new EncodingsReport(rawTrackEncodings);
};

export const onEncodingsUpdate = (
  msg: ConsoleMessage,
  peerToken: PeerToken,
) => {
  const content = msg.text().trim();
  if (content.startsWith("trackEncodings:")) {
    rawTrackEncodings.set(peerToken, content.slice("trackEncodings:".length));
  }
};
