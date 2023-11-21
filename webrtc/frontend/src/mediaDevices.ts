import { AUDIO_TRACK_CONSTRAINTS, VIDEO_TRACK_CONSTRAINTS } from "./constraints";

export const startDevices = async () => {
  await navigator.mediaDevices.getUserMedia({ audio: true, video: true });
  const devices = await navigator.mediaDevices.enumerateDevices();

  let mediaStreams: MediaStream[] = [];

  for (const kind of ["audio", "video"]) {
    const device = devices.filter((device) => device.kind === `${kind}input`)[0];
    console.log(`${kind} device: ${JSON.stringify(device)}`);

    const stream = await startDevice(device.deviceId, kind as MediaKind);
    mediaStreams.push(stream);
  }

  return mediaStreams;
};

const startDevice = async (deviceId: string, type: MediaKind) => {
  const stream: MediaStream = await navigator.mediaDevices.getUserMedia({
    [type]: { deviceId: deviceId, ...(type === "video" ? VIDEO_TRACK_CONSTRAINTS : AUDIO_TRACK_CONSTRAINTS) },
  });

  return stream;
};
