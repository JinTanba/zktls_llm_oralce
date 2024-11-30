import { Signer } from "ethers";
import { Provider } from "@ethersproject/providers";
import type { IL1Messenger } from "./IL1Messenger";
export declare class IL1MessengerFactory {
    static connect(address: string, signerOrProvider: Signer | Provider): IL1Messenger;
}
