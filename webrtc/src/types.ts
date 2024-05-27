import { TrackEncoding } from "@fishjam-dev/ts-client";

export type Args = {
  fishjamAddress: string;
  fishjamToken: string;
  secure: boolean;
  peers: number;
  peersPerRoom: number;
  duration: number;
  peerDelay: number;
  chromeExecutable: string;
  peersPerBrowser: number;
  activePeers: number;
  targetEncoding: TrackEncoding;
  availableEncodings: TrackEncoding[];
};

export type PeerResponse = {
  data: {
    token: string;
    peer: object;
  };
};

export type RoomResponse = {
  data: {
    fishjam_address: string;
    room: Room;
  };
};

export type RoomsResponse = {
  data: Array<Room>;
};

export type Room = {
  id: string;
  components: object;
  peers: object;
  config: object;
};

export type FishjamConfig = {
  fishjamAddress: string;
  secure: boolean;
  targetEncoding: TrackEncoding;
  activeEncodings: TrackEncoding[];
};

export type RawTrackEncodings = Map<PeerToken, RemoteTrackEncodings>;

export type PeerToken = string;
type RemoteTrackEncodings = string;
