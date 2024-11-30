import { Signer } from "ethers";
import { Provider } from "@ethersproject/providers";
import type { IERC1271 } from "./IERC1271";
export declare class IERC1271Factory {
    static connect(address: string, signerOrProvider: Signer | Provider): IERC1271;
}
