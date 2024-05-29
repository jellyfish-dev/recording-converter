import { RoomResponse, PeerResponse, RoomsResponse, Room } from "./types";

import { RoomApi } from "../server-sdk";
import axios from "axios";

export class Client {
  api: RoomApi;

  constructor({
    fishjamAddress,
    fishjamToken,
    secure,
  }: {
    fishjamAddress: string;
    fishjamToken: string;
    secure: boolean;
  }) {
    const protocol = secure ? "https" : "http";
    const jfAddress = `${protocol}://${fishjamAddress}`;

    this.api = new RoomApi(
      undefined,
      jfAddress,
      axios.create({
        headers: {
          Authorization: `Bearer ${fishjamToken}`,
        },
      }),
    );
  }

  createRoom = async (roomId: string) => {
    return (
      await this.api.createRoom({
        roomId: roomId,
        videoCodec: "h264",
        peerlessPurgeTimeout: 5,
      })
    ).data.data;
  };

  addPeer = async (roomId: string) => {
    return (
      await this.api.addPeer(roomId, {
        type: "webrtc",
        options: { enableSimulcast: true },
      })
    ).data.data;
  };

  addHls = async (roomId: string) => {
    return (
      await this.api.addComponent(roomId, {
        type: "hls",
        options: { lowLatency: false },
      })
    ).data.data;
  };

  purge = async () => {
    this.api.getAllRooms().then((response) => {
      response.data.data.forEach((room: Room) => {
        this.api.deleteRoom(room.id);
      });
    });
  };
}
