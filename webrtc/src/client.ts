import { RoomResponse, PeerResponse, RoomsResponse } from "./types";

export class Client {
  jellyfishAddress: string;
  jellyfishToken: string;

  constructor({
    jellyfishAddress,
    jellyfishToken,
    secure,
  }: {
    jellyfishAddress: string;
    jellyfishToken: string;
    secure: boolean;
  }) {
    const protocol = secure ? "https" : "http";

    this.jellyfishAddress = `${protocol}://${jellyfishAddress}`;
    this.jellyfishToken = jellyfishToken;
  }

  createRoom = async () => {
    const response = await this.request("POST", "/room/");

    const content: RoomResponse = (await response.json()) as RoomResponse;
    return content.data.room.id;
  };

  addPeer = async (roomId: string) => {
    const response = await this.request("POST", `/room/${roomId}/peer`, {
      type: "webrtc",
      options: {},
    });

    const content: PeerResponse = (await response.json()) as PeerResponse;
    return content.data.token;
  };

  purge = async () => {
    const roomsResponse = await this.request("GET", "/room");

    const content: RoomsResponse =
      (await roomsResponse.json()) as RoomsResponse;

    const promises = content.data.map((room) =>
      this.request("DELETE", `/room/${room.id}`),
    );
    await Promise.all(promises);
  };

  private request = async (
    method: "GET" | "POST" | "DELETE",
    path: string,
    body?: object,
  ) => {
    const response = await fetch(`${this.jellyfishAddress}${path}`, {
      method: method,
      body: JSON.stringify(body),
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        authorization: `Bearer ${this.jellyfishToken}`,
      },
    });

    return response;
  };
}
