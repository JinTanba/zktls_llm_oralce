import { Signer } from "ethers";
import { Provider } from "@ethersproject/providers";
import type { ContractDeployer } from "./ContractDeployer";
export declare class ContractDeployerFactory {
    static connect(address: string, signerOrProvider: Signer | Provider): ContractDeployer;
}
