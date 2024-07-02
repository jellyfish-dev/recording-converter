import { ConsoleMessage } from "playwright";
import { PeerToken, RawRtcScores, RawTrackEncodings } from "./types";

const fs = require("fs");

let rawTrackEncodings: RawTrackEncodings = new Map();
let rawTrackScores: RawRtcScores = new Map();

export const reportToString = () => {
  const encoding = new EncodingsReport(rawTrackEncodings).toString();
  const rtcScore = new RtcScoreReport(rawTrackScores).toString();

  return `Encodings: ${encoding}, RtcScore: ${rtcScore}`;
};


export const createReportCSV = (path: string) => {
  const csv_columns = `timestamp,min,max,q1,q2,q3,low,mid,high\n`
  fs.writeFile(path, csv_columns, () => {});
}

export const appendReportCSV = (path: string, timestamp: number) => {
  const encoding = new EncodingsReport(rawTrackEncodings);
  const rtcScore = new RtcScoreReport(rawTrackScores);

  if (rtcScore.report === null) return;

  const report = { ...rtcScore.report, encoding: encoding.report };

  // duration,min,max,q1,q2,q3,low,mid,high
  const newLine = `${timestamp},${report.min.toFixed(2)},${report.max.toFixed(2)},${report.quartiles.Q1.toFixed(2)},${report.quartiles.Q2.toFixed(2)},${report.quartiles.Q3.toFixed(2)},${report.encoding.l},${report.encoding.m},${report.encoding.h}\n`;

  fs.appendFile(path, newLine, (err: any) => {});
};


export const onConsoleMessage = (msg: ConsoleMessage, peerToken: PeerToken) => {
  const content = msg.text().trim();

  if (content.startsWith("trackEncodings:"))
    onEncodingsUpdate(content, peerToken);

  if (content.startsWith("scores:")) onScoreUpdate(content, peerToken);
};

class EncodingsReport {
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

export class RtcScoreReport {
  report: {
    min: number;
    max: number;
    quartiles: Record<string, number>;
  } | null;

  constructor(reportRaw: RawRtcScores) {
    const values = Array.from(reportRaw.values())
      .flat()
      .sort((a, b) => a - b);

    if (values.length < 4) {
      this.report = null;
      return;
    }

    const quartiles = this.quartiles(values);

    this.report = {
      min: values[0],
      max: values[values.length - 1],
      quartiles: quartiles,
    };
  }

  toString = () => {
    if (this.report === null) return `null`;

    const quartiles = `Q1: ${this.report.quartiles.Q1.toFixed(
      2
    )}, Q2: ${this.report.quartiles.Q2.toFixed(
      2
    )}, Q3: ${this.report.quartiles.Q3.toFixed(2)}`;

    return `min: ${this.report.min.toFixed(2)}, max: ${this.report.max.toFixed(
      2
    )}, quartiles: ${quartiles}`;
  };

  private median = (values: Array<number>) => {
    const mid = Math.floor(values.length / 2);

    return values.length % 2 === 0
      ? (values[mid - 1] + values[mid]) / 2
      : values[mid];
  };

  private quartiles = (values: Array<number>) => {
    const lowerHalf = values.slice(0, Math.floor(values.length / 2));
    const upperHalf = values.slice(Math.ceil(values.length / 2));

    const Q1 = this.median(lowerHalf);
    const Q2 = this.median(values);
    const Q3 = this.median(upperHalf);

    return { Q1: Q1, Q2: Q2, Q3: Q3 };
  };
}

const onScoreUpdate = (content: string, peerToken: PeerToken) => {
  const scores = JSON.parse(content.slice("scores:".length));
  rawTrackScores.set(peerToken, scores);
};

const onEncodingsUpdate = (content: string, peerToken: PeerToken) => {
  rawTrackEncodings.set(peerToken, content.slice("trackEncodings:".length));
};
