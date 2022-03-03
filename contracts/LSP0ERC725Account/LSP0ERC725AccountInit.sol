// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

// modules
import "./LSP0ERC725AccountInitAbstract.sol";

/**
 * @title Deployable Proxy Implementation of ERC725Account
 * @author Fabian Vogelsteller <fabian@lukso.network>, Jean Cavallera (CJ42), Yamen Merhi (YamenMerhi)
 * @dev Bundles ERC725X and ERC725Y, ERC1271 and LSP1UniversalReceiver and allows receiving native tokens
 */
contract LSP0ERC725AccountInit is LSP0ERC725AccountInitAbstract {
    /**
     * @notice Sets the owner of the contract and register ERC725Account, ERC1271 and LSP1UniversalReceiver interfacesId
     * @param _newOwner the owner of the contract
     */
    function initialize(address _newOwner) public virtual override initializer {
        LSP0ERC725AccountInitAbstract._initialize(_newOwner);
    }
}
