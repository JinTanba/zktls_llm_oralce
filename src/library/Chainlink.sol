// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Oracle.sol";

library Reasoning {
    using FunctionsRequest for FunctionsRequest.Request;

    event OnchainReasoning(uint256 indexed actionId, bytes result, address client, address sender, string[] args, bytes[] bytesArgs);
    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event LinkReport(uint256 oldBalance, uint256 newBalance);

    function executeAction(
        bytes memory encryptedSecretsUrls,
        Schema.FunctionArgs memory functionArgs,
        uint256 sendAmount,
        address linkOwner,
        address clientAddress
    ) internal returns(bytes32) {
        Schema.Config storage config = Storage.config();
        uint256 oldBalance = getSubscriptionBalance(config.router, config.subscriptionId);
        Schema.ReasoningParams storage params = Storage.reasoningParams();
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(params.code);
        req.addSecretsReference(encryptedSecretsUrls);
        req.setArgs(setArgs(functionArgs.args, params.prompt));
        req.setBytesArgs(functionArgs.bytesArgs);
        
        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            config.subscriptionId,
            config.gasLimit,
            config.donID
        );
        
        Schema.Promise storage stack = Storage.stack(requestId);
        stack.clientAddress = clientAddress;
        stack.actionId = actionId;
        stack.functionArgs = functionArgs;
        stack.sender = linkOwner;
        stack.oldBalance = oldBalance;
        
        return requestId;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal {
        Schema.Promise memory stack = Storage.stack(requestId);
        Schema.Config storage config = Storage.config();
        
        uint256 payedLink = Storage.linkDeposit()[stack.sender];
        uint256 newBalance = getSubscriptionBalance(config.router, config.subscriptionId);
        emit LinkReport(stack.oldBalance, newBalance);
        
        uint256 usedLink = stack.oldBalance - newBalance;
        
        IReasoning(stack.clientAddress).reasoningCallback(requestId, response, stack.sender);
        
        refundLink(payedLink - usedLink, stack.sender, config.link, config.router, config.subscriptionId);
        
        emit OnchainReasoning(stack.actionId, response, stack.clientAddress, stack.sender, stack.functionArgs.args, stack.functionArgs.bytesArgs);
        emit Response(requestId, response, err);
    }

    function setArgs(string[] memory args, string memory prompt) internal pure returns(string[] memory) {
        string[] memory completeArgs = new string[](args.length + 1);
        completeArgs[0] = prompt;
        for(uint i = 0; i < args.length; i++) {
            completeArgs[i+1] = args[i];
        }
        return completeArgs;
    }

    function getSubscriptionBalance(address router, uint64 subscriptionId) internal view returns(uint256) {
        return IRouterForGetSubscriptionBalance(router).getSubscription(subscriptionId).balance;
    }

    function refundLink(uint256 amount, address sender, address link, address router, uint64 subscriptionId) internal {
        IERC677(link).transferAndCall(router, amount, abi.encode(subscriptionId));
        uint256 depositBalance = Storage.linkDeposit()[sender];
        if(depositBalance > amount) {
            IERC20(link).transfer(sender, depositBalance - amount);
        }
        Storage.linkDeposit()[sender] -= amount;
    }
}