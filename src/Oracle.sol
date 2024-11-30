// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
 
import "@reclaimprotocol/verifier-solidity-sdk/contracts/Reclaim.sol";
import "@reclaimprotocol/verifier-solidity-sdk/contracts/Addresses.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";


interface IPlopNFT is IERC721 {
    function mint(address to) external returns (uint256);
    function minter() external view returns (address);
    function setMinter(address _newMinter) external;
    function tokenURI(uint256 tokenId) external view returns (string memory);
    
    event MinterChanged(address indexed previousMinter, address indexed newMinter);
    event NFTMinted(address indexed to, uint256 indexed tokenId);
}

library Utils {
    function extractValue(string memory json, string memory key) public pure returns (string memory) {
        string memory quotedKey = string(abi.encodePacked('"', key, '":'));
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(quotedKey);
        
        uint i = 0;
        while (i < jsonBytes.length - keyBytes.length) {
            bool found = true;
            for (uint j = 0; j < keyBytes.length; j++) {
                if (jsonBytes[i + j] != keyBytes[j]) {
                    found = false;
                    break;
                }
            }
            
            if (found) {
                uint valueStart = i + keyBytes.length;
                while (valueStart < jsonBytes.length && jsonBytes[valueStart] == ' ') {
                    valueStart++;
                }
                
                uint valueEnd = valueStart;
                bool isString = jsonBytes[valueStart] == '"';
                bool isObject = jsonBytes[valueStart] == '{';
                
                if (isString) {
                    valueStart++;
                    valueEnd = valueStart;
                    while (valueEnd < jsonBytes.length) {
                        if (jsonBytes[valueEnd] == '"' && jsonBytes[valueEnd-1] != "\\") {
                            break;
                        }
                        valueEnd++;
                    }
                } else if (isObject) {
                    uint openBraces = 1;
                    valueEnd = valueStart + 1;
                    while (valueEnd < jsonBytes.length && openBraces > 0) {
                        if (jsonBytes[valueEnd] == '{') {
                            openBraces++;
                        } else if (jsonBytes[valueEnd] == '}') {
                            openBraces--;
                        }
                        if (openBraces > 0) {
                            valueEnd++;
                        }
                    }
                    valueEnd++;
                } else {
                    while (valueEnd < jsonBytes.length) {
                        if (jsonBytes[valueEnd] == ',' || jsonBytes[valueEnd] == '}') {
                            break;
                        }
                        valueEnd++;
                    }
                }
                
                bytes memory value = new bytes(valueEnd - valueStart);
                for (uint j = 0; j < valueEnd - valueStart; j++) {
                    value[j] = jsonBytes[valueStart + j];
                }
                
                return string(value);
            }
            i++;
        }
        
        return "";
    }

    function getFromExtractedParams(string memory json, string memory paramKey) public pure returns (string memory) {
        string memory extractedParams = extractValue(json, "extractedParameters");
        if (bytes(extractedParams).length == 0) {
            return "";
        }
        return extractValue(extractedParams, paramKey);
    }

    function stringToAddress(string memory _address) public pure returns (address) {
        bytes memory tmp = bytes(_address);
        require(tmp.length == 42 && tmp[0] == '0' && tmp[1] == 'x', "Invalid address format");
        
        bytes20 result;
        uint160 value = 0;
        
        for (uint i = 2; i < 42; i++) {
            bytes1 char = tmp[i];
            uint8 digit;
            
            if (uint8(char) >= 48 && uint8(char) <= 57) {
                digit = uint8(char) - 48;
            } else if (uint8(char) >= 65 && uint8(char) <= 70) {
                digit = uint8(char) - 55;
            } else if (uint8(char) >= 97 && uint8(char) <= 102) {
                digit = uint8(char) - 87;
            } else {
                revert("Invalid character in address");
            }
            
            value = value * 16 + digit;
        }
        
        result = bytes20(value);
        return address(result);
    }

    function stringToUint(string memory _str) public pure returns (uint256) {
        bytes memory b = bytes(_str);
        uint256 result = 0;
        
        for(uint i = 0; i < b.length; i++) {
            uint8 char = uint8(b[i]);
            require(char >= 48 && char <= 57, "Invalid character");
            result = result * 10 + (char - 48);
        }
        
        return result;
    }
}

contract Attestor {
    address public reclaimAddress;
    uint256 public dropCount;
    uint256 public questCount;
    address public immutable owner;

    enum QuestType {
        IS_INCLUDED_IN_LIST,
        LESS,
        MORE,
        EQUAL,
        PASS
    }

    struct Drop {
        address rewardTokenAddress;
        uint256 rewardAmount;
        uint256[] questList;
        uint256 deposit;
        address creator;
        bool isNFT;
    }

    struct Quest {
        string[] targetKeys;
        string[] expectedValues;
        QuestType[] questTypes;
        string providerHash;
    }

    mapping(uint256 => Drop) public drops;
    mapping(uint256 => Quest) public quests;
    mapping(address => mapping(uint256 => bool)) public complited;
    mapping(uint256 => address) public claimDrop;

    event DropCreated(
        uint256 dropId,
        address rewardTokenAddress,
        uint256 rewardAmount,
        uint256[] questList,
        address creator
    );

    event QuestCreated(
        uint256 questId,
        uint256 dropId,
        string[] targetKeys,
        string[] expectedValues,
        QuestType[] questTypes,
        string providerHash
    );

    constructor() {
        reclaimAddress = Addresses.BASE_SEPOLIA;
        owner = msg.sender;
    }

    function createDrop(
        address rewardTokenAddress,
        uint256 rewardAmount,
        address creator,
        bool isNFT
    ) external returns (uint256) {
        dropCount += 1;
        Drop storage drop = drops[dropCount];
        drop.rewardTokenAddress = rewardTokenAddress;
        drop.rewardAmount = rewardAmount;
        drop.creator = creator;
        drop.isNFT = isNFT;
        emit DropCreated(
            dropCount,
            rewardTokenAddress,
            rewardAmount,
            new uint256[](0),
            creator
        );
        return dropCount;
    }

    function createQuest(
        uint256 dropId,
        string[] memory targetKeys,
        string[] memory expectedValues,
        QuestType[] memory questTypes,
        string memory providerHash
    ) external returns (uint256) {
        require(targetKeys.length == expectedValues.length && expectedValues.length == questTypes.length, "Arrays length mismatch");
        require(targetKeys.length > 0, "Empty arrays not allowed");

        questCount += 1;
        Quest storage quest = quests[questCount];
        
        quest.targetKeys = targetKeys;
        quest.expectedValues = expectedValues;
        quest.questTypes = questTypes;
        quest.providerHash = providerHash;

        Drop storage drop = drops[dropId];
        drop.questList.push(questCount);

        emit QuestCreated(
            questCount,
            dropId,
            targetKeys,
            expectedValues,
            questTypes,
            providerHash
        );
        return questCount;
    }

    function verifyProof(Reclaim.Proof memory proof, uint256 questId, uint256 dropId) external {
        require(msg.sender == owner, "only owner can verify proof");
        address sender = getSender(proof.claimInfo.context);
        
        Reclaim(reclaimAddress).verifyProof(proof);
        Quest storage quest = quests[questId];
        
        require(!complited[sender][questId], "you have already complited");

        for(uint256 i = 0; i < quest.targetKeys.length; i++) {
            if(quest.questTypes[i] == QuestType.IS_INCLUDED_IN_LIST) {
                isIncludedInList(proof.claimInfo.context, quest.targetKeys[i], quest.expectedValues[i]);
            } else if(quest.questTypes[i] != QuestType.PASS) {
                valueComparison(proof.claimInfo.context, quest.targetKeys[i], quest.expectedValues[i], quest.questTypes[i]);
            }
        }
        
        // require(quest.providerHash == checkProviderHash(proof.claimInfo.context), "provider hash mismatch"); TODO: プロバイダーハッシュのチェックを追加

        complited[sender][questId] = true;
        
        if(checkDropComplite(drops[dropId], sender)){
            claimReward(drops[dropId].creator, dropId, sender);
        }
    }

    function getSender(string memory context) internal pure returns (address) {
        string memory sender = Utils.extractValue(context, "contextAddress");
        return Utils.stringToAddress(sender);
    }

    function claimReward(
        address creator,
        uint256 dropId,
        address sender
    ) internal {
        Drop memory drop = drops[dropId];
        if(drop.isNFT){
            IPlopNFT(drop.rewardTokenAddress).mint(sender);
        } else {
            IERC20(drop.rewardTokenAddress).transferFrom(creator, sender, drop.rewardAmount);
        }
    }

    function recoverSigner(bytes memory signature, uint256 questId, address sender) public pure returns (address) {
        return ECDSA.recover(keccak256(abi.encodePacked(questId, sender)), signature);
    }

    function checkDropComplite(Drop memory drop, address sender) internal view returns (bool) {
        for (uint256 i = 0; i < drop.questList.length; i++) {
            if(!complited[sender][drop.questList[i]]) {
                return false;
            }
        }
        return true;
    }

    function getDropQuestList(uint256 dropId) external view returns (uint256[] memory) {
        return drops[dropId].questList;
    }

    function getDropDetails(uint256 dropId) external view returns (
        address rewardTokenAddress,
        uint256 rewardAmount,
        uint256[] memory questList,
        uint256 deposit,
        address creator
    ) {
        Drop storage drop = drops[dropId];
        return (
            drop.rewardTokenAddress,
            drop.rewardAmount,
            drop.questList,
            drop.deposit,
            drop.creator
        );
    }

    function getQuestDetails(uint256 questId) external view returns (
        string[] memory targetKeys,
        string[] memory expectedValues,
        QuestType[] memory questTypes,
        string memory providerHash
    ) {
        Quest storage quest = quests[questId];
        return (
            quest.targetKeys,
            quest.expectedValues,
            quest.questTypes,
            quest.providerHash
        );
    }

    function isIncludedInList(
        string memory context,
        string memory targetKey,
        string memory expectedValue
    ) internal pure {
        string memory extractedValue = Utils.getFromExtractedParams(context, targetKey);
        require(
            keccak256(abi.encodePacked(extractedValue)) == keccak256(abi.encodePacked(expectedValue)),
            "not match"
        );
    }

    function valueComparison(
        string memory context,
        string memory targetKey,
        string memory expectedValue,
        QuestType questType
    ) internal pure {
        string memory extractedValue = Utils.getFromExtractedParams(context, targetKey);
        uint256 uint256ExpectedValue = Utils.stringToUint(expectedValue);
        uint256 uint256ExtractedValue = Utils.stringToUint(extractedValue);

        if(questType == QuestType.LESS) {
            require(uint256ExtractedValue < uint256ExpectedValue, "not less");
        } else if(questType == QuestType.MORE) {
            require(uint256ExtractedValue > uint256ExpectedValue, "not more");
        } else if(questType == QuestType.EQUAL) {
            require(uint256ExtractedValue == uint256ExpectedValue, "not equal");
        }
    }
}