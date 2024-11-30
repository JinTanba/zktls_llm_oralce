import { Signer } from "ethers";
import { Provider } from "@ethersproject/providers";
import type { IPaymasterFlow } from "./IPaymasterFlow";
export declare class IPaymasterFlowFactory {
    static connect(address: string, signerOrProvider: Signer | Provider): IPaymasterFlow;
}
