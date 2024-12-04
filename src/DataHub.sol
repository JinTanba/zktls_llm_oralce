// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@reclaimprotocol/verifier-solidity-sdk/contracts/Reclaim.sol";
import "@reclaimprotocol/verifier-solidity-sdk/contracts/Addresses.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

library Schema {

    struct Ids {
        uint256 articleId;
        uint256 propositionId;
        uint256 providerId;
        uint256 actionId;
    }

    struct Config {
        address router;
        bytes32 donID;
        address link;
        uint32 gasLimit;
        uint64 subscriptionId;
    }

    struct Article {
        string content;
        address createdBy;
        uint256 createdAt;
        uint256 providerId;
    }

    struct Proposition {
        string proposition;
        uint256[] permittedProviderIds;
    }

    struct Provider{
         string[] keys;
         bytes32 providerHash;
    }

}

library Storage {
    uint256 constant IDS_SLOT = 1;
    uint256 constant ARTICLE_SLOT = 2;
    uint256 constant PROPOSITION_SLOT = 3;
    uint256 constant PROVIDER_SLOT = 4;

    function article(uint256 id) internal pure returns(Schema.Article storage s) {
        assembly {
            mstore(0, ARTICLE_SLOT)
            mstore(32, id)
            s.slot := keccak256(0, 64)
        }
    }

    function proposition(uint256 id) internal pure returns(Schema.Proposition storage s) {
        assembly {
            mstore(0, PROPOSITION_SLOT)
            mstore(32, id)
            s.slot := keccak256(0, 64)
        }
    }

    function provider(uint256 id) internal pure returns(Schema.Provider storage s) {
        assembly {
            mstore(0, PROVIDER_SLOT)
            mstore(32, id)
            s.slot := keccak256(0, 64)
        }
    }

    function ids() internal pure returns(Schema.Ids storage s) {
        assembly {
            mstore(0, IDS_SLOT)
            s.slot := keccak256(0, 32)
        }
    }
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

contract DataHub {

    event ProviderCreated(uint256 indexed id, string providerHash);
    event ArticleCreated(uint256 indexed id, string content, address creator);
    event PropositionCreated(uint256 indexed id, string proposition);

    
    function verifyProof(Reclaim.Proof memory proof, uint256 providerId) external {
        Schema.Ids storage ids = Storage.ids();
        Schema.Provider storage provider = Storage.provider(providerId);
        Reclaim(Addresses.BASE_SEPOLIA).verifyProof(proof);
        string memory providerHashInStr = Utils.getFromExtractedParams(proof.claimInfo.context, "providerHash");
        require(provider.providerHash == keccak256(bytes(providerHashInStr)), "wrong data provider");

        string memory result;
        for(uint256 i = 0;i < provider.keys.length; i++) {
            string memory key = provider.keys[i];
            string memory value = Utils.getFromExtractedParams(proof.claimInfo.context, provider.keys[i]);
            string memory line = string(abi.encodePacked(key, ": ", value, "\n"));
            result = string(abi.encodePacked(result, line));
        }
        
        uint256 newArticleId = ++ids.articleId;
        Schema.Article storage article = Storage.article(newArticleId);
        article.content = result;
        article.createdBy = msg.sender;
        article.createdAt = block.timestamp;
    }

   function createProvider(string memory providerHash, string[] memory keys) external returns (uint256) {
       Schema.Ids storage ids = Storage.ids();
       uint256 newProviderId = ++ids.providerId;
       
       Schema.Provider storage provider = Storage.provider(newProviderId);
       provider.providerHash = keccak256(bytes(providerHash));
       provider.keys = keys;

       emit ProviderCreated(newProviderId, providerHash);
       return newProviderId;
   }


   function createProposition(string memory proposition, uint256[] memory providerIds) external returns (uint256) {
       Schema.Ids storage ids = Storage.ids();
       uint256 newPropositionId = ++ids.propositionId;
       
       Schema.Proposition storage newProposition = Storage.proposition(newPropositionId);
       newProposition.proposition = proposition;
       newProposition.permittedProviderIds = providerIds;

       emit PropositionCreated(newPropositionId, proposition);
       return newPropositionId;
   }

   function getProvider(uint256 providerId) external pure returns (Schema.Provider memory) {
       return Storage.provider(providerId);
   }

   function getArticle(uint256 articleId) external pure returns (Schema.Article memory) {
       return Storage.article(articleId);
   }

   function getProposition(uint256 propositionId) external pure returns (Schema.Proposition memory) {
       return Storage.proposition(propositionId);
   }

   // 既存コードの実装
   function getArticles(uint256[] memory articleIds) external view returns (string[] memory) {
       string[] memory articles =  new string[](articleIds.length);
       for(uint i = 0; i < articleIds.length; i++) {
           articles[i] = Storage.article(articleIds[i]).content;
       }
       return articles;
   }

}