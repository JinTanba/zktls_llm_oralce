// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC677 {
    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);

    function transferAndCall(address to, uint256 amount, bytes memory data) external returns (bool);
}

interface IRouterForGetSubscriptionBalance {
    struct Subscription {
        uint96 balance;
        address owner;
        uint96 blockedBalance;
        address proposedOwner;
        address[] consumers;
        bytes32 flags;
    }

    function getSubscription(uint64 subscriptionId) external view returns (Subscription memory);
}

interface IDataHub {
    struct Article {
        string summary;
        string firstParagraph;
        string webUrl;
        string pubDate;
        address createdBy;
        uint256 createdAt;
        uint256 providerId;
    }

    function getProposition(uint256) external view returns (string memory);
    function getArticles(uint256[] memory) external view returns (string[] memory);
}

contract ReasoningHub is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    constructor(
        address _router,
        bytes32 _donID,
        address _link,
        uint32 _gasLimit,
        uint64 _subscriptionId,
        string memory code,
        string memory prompt
    ) FunctionsClient(_router) ConfirmedOwner(msg.sender) {
        Types.Config storage config = Storage._config();
        config.router = _router;
        config.donID = _donID;
        config.link = _link;
        config.gasLimit = _gasLimit;
        config.subscriptionId = _subscriptionId;
        config.code = code;
        config.prompt = prompt;
    }

    event OnchainReasoning(
        uint256 indexed actionId, bytes result, address client, address sender, string[] args, bytes[] bytesArgs
    );
    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event SetSubscription(uint256 subscriptionId, address sender);

    function getSubscriptionBalance() public view returns (uint256) {
        Types.Config storage config = Storage._config();
        return IRouterForGetSubscriptionBalance(config.router).getSubscription(config.subscriptionId).balance;
    }

    function execute(
        bytes memory encryptedSecretsUrls,
        uint256 proposionId,
        uint256[] memory articleIds,
        uint256 sendAmount,
        address linkOwner
    ) external returns (bytes32) {
        Types.Config storage config = Storage._config();
        uint256 oldBalance = getSubscriptionBalance();
        Types.FunctionArgs memory functionArgs = createFunctionArgs(proposionId, articleIds, config);
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(config.code);
        req.addSecretsReference(encryptedSecretsUrls);
        req.setArgs(functionArgs.args); // args[0]: prompt, args[1]: proposion
        req.setBytesArgs(functionArgs.bytesArgs);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), config.subscriptionId, config.gasLimit, config.donID);

        Storage._stack(requestId).clientAddress = msg.sender;
        Storage._stack(requestId).sender = linkOwner;
        Storage._stack(requestId).oldBalance = oldBalance;

        depositLink(linkOwner, sendAmount);
        return requestId;
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        Types.Promise memory _promise = Storage._stack(requestId);
        uint256 payedLink = Storage._linkDeposit()[_promise.sender];
        uint256 newBalance = getSubscriptionBalance();
        uint256 usedLink = _promise.oldBalance - newBalance;
        //TODO: New Idea!!!
        //executeの際に、定数ETHをステークしてもらう。
        //LLMは、全く無関係なニュースを受け取った場合に、特別な値を返却する
        //その場合は、全く無関係なニュースを提供し、結果を撹乱しようとした罰則として、ステーク料を没収する!!!と
        //callback-----
        // IReasoning(_promise.clientAddress).reasoningCallback(requestId, response, _promise.sender); TODO how to get result
        //-------------
        refund(payedLink - usedLink, _promise.sender);
        // emit OnchainReasoning(_promise.actionId, response, _promise.clientAddress, _promise.sender);
        emit Response(requestId, response, err);
    }

    function createFunctionArgs(uint256 proposionId, uint256[] memory articleIds, Types.Config storage config)
        internal
        view
        returns (Types.FunctionArgs memory functionArgs)
    {
        string memory proposion = IDataHub(config.dataHub).getProposition(proposionId);
        bytes memory articles = abi.encode(IDataHub(config.dataHub).getArticles(articleIds));
        string memory prompt = config.prompt;
        functionArgs.args[0] = prompt;
        functionArgs.args[1] = proposion;
        functionArgs.bytesArgs[0] = articles;
    }

    // LINK token management functions
    function depositLink(address to, uint256 sendAmount) public {
        Storage._linkDeposit()[to] += sendAmount;
        Types.Config storage config = Storage._config();
        IERC20(config.link).transferFrom(to, address(this), sendAmount);
    }

    function refund(uint256 amount, address sender) internal {
        Types.Config storage config = Storage._config();
        IERC677(config.link).transferAndCall(config.router, amount, abi.encode(config.subscriptionId));
        uint256 depositBalance = Storage._linkDeposit()[sender];
        if (depositBalance > amount) {
            IERC20(config.link).transfer(sender, depositBalance - amount);
        }
        Storage._linkDeposit()[sender] -= amount;
    }
}

library Types {
    struct Config {
        address router;
        bytes32 donID;
        address link;
        uint32 gasLimit;
        uint64 subscriptionId;
        string code;
        string prompt;
        address dataHub;
    }

    struct Action {
        string prompt;
        string code;
    }

    struct FunctionArgs {
        string[] args;
        bytes[] bytesArgs;
    }

    struct Promise {
        address clientAddress;
        uint256 actionId;
        address sender;
        uint256 oldBalance;
    }
}

library Storage {
    uint8 constant SUBSCRIPTION_SLOT = 1;
    uint8 constant ACTION_SLOT = 2;
    uint8 constant STACK_SLOT = 3;
    uint8 constant LINK_DEPOSIT_SLOT = 4;
    uint8 constant CONFIG_SLOT = 5;

    function _action(uint256 id) internal pure returns (Types.Action storage _s) {
        assembly {
            mstore(0, ACTION_SLOT)
            mstore(32, id)
            _s.slot := keccak256(0, 64)
        }
    }

    function _subscription() internal pure returns (mapping(address => uint64) storage _s) {
        assembly {
            mstore(0, SUBSCRIPTION_SLOT)
            _s.slot := keccak256(0, 32)
        }
    }

    function _stack(bytes32 requestId) internal pure returns (Types.Promise storage _s) {
        assembly {
            mstore(0, STACK_SLOT)
            mstore(32, requestId)
            _s.slot := keccak256(0, 64)
        }
    }

    function _linkDeposit() internal pure returns (mapping(address => uint256) storage _s) {
        assembly {
            mstore(0, LINK_DEPOSIT_SLOT)
            _s.slot := keccak256(0, 32)
        }
    }

    function _config() internal pure returns (Types.Config storage _s) {
        assembly {
            mstore(0, CONFIG_SLOT)
            _s.slot := keccak256(0, 32)
        }
    }
}
