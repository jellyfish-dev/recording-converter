type PeerMetadata = {
  name: string;
};

type TrackMetadata = {
  type: "camera" | "microphone" | "screenshare";
};

type MediaKind = "audio" | "video";

type QueryParams = {
  peerToken: string;
  activePeer: boolean;
};
