// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.5;

// modules
import {ERC725Y} from "@erc725/smart-contracts/contracts/ERC725Y.sol";

// libraries
import {GasLib} from "../../Utils/GasLib.sol";
import {LSP6Utils} from "../LSP6Utils.sol";

// constants
import {
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX,
    _LSP6KEY_ADDRESSPERMISSIONS_PREFIX,
    _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
    _LSP6KEY_ADDRESSPERMISSIONS_ALLOWEDCALLS_PREFIX,
    _LSP6KEY_ADDRESSPERMISSIONS_AllowedERC725YDataKeys_PREFIX,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_ADDCONTROLLER,
    _PERMISSION_EDITPERMISSIONS,
    _PERMISSION_ADDEXTENSIONS,
    _PERMISSION_CHANGEEXTENSIONS,
    _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE,
    _PERMISSION_CHANGEUNIVERSALRECEIVERDELEGATE
} from "../LSP6Constants.sol";
import {
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX,
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY
} from "../../LSP1UniversalReceiver/LSP1Constants.sol";
import {_LSP17_EXTENSION_PREFIX} from "../../LSP17ContractExtension/LSP17Constants.sol";

// errors
import {
    NotRecognisedPermissionKey,
    AddressPermissionArrayIndexValueNotAnAddress,
    InvalidEncodedAllowedCalls,
    InvalidEncodedAllowedERC725YDataKeys,
    NoERC725YDataKeysAllowed,
    NotAllowedERC725YDataKey,
    NotAuthorised
} from "../LSP6Errors.sol";

abstract contract LSP6SetDataModule {
    using LSP6Utils for *;

    /**
     * @dev verify if the `controllerAddress` has the permissions required to set a data key on the ERC725Y storage of the `controlledContract`.
     * @param controlledContract the address of the ERC725Y contract where the data key is set.
     * @param controllerAddress the address of the controller who wants to set the data key.
     * @param controllerPermissions the permissions of the controller address.
     * @param inputDataKey the data key to set on the `controlledContract`.
     * @param inputDataValue the data value to set for the `inputDataKey`.
     */
    function _verifyCanSetData(
        address controlledContract,
        address controllerAddress,
        bytes32 controllerPermissions,
        bytes32 inputDataKey,
        bytes memory inputDataValue
    ) internal view virtual {
        bytes32 requiredPermission = _getPermissionRequiredToSetDataKey(
            controlledContract,
            inputDataKey,
            inputDataValue
        );

        // CHECK if allowed to set an ERC725Y Data Key
        if (requiredPermission == _PERMISSION_SETDATA) {
            // Skip if caller has SUPER permissions
            if (controllerPermissions.hasPermission(_PERMISSION_SUPER_SETDATA)) return;

            _requirePermissions(controllerAddress, controllerPermissions, _PERMISSION_SETDATA);

            _verifyAllowedERC725YSingleKey(
                controllerAddress,
                inputDataKey,
                ERC725Y(controlledContract).getAllowedERC725YDataKeysFor(controllerAddress)
            );
        } else {
            // Otherwise CHECK the required permission if setting LSP6 permissions, LSP1 Delegate or LSP17 Extensions.
            _requirePermissions(controllerAddress, controllerPermissions, requiredPermission);
        }
    }

    /**
     * @dev verify if the `controllerAddress` has the permissions required to set an array of data keys on the ERC725Y storage of the `controlledContract`.
     * @param controlledContract the address of the ERC725Y contract where the data key is set.
     * @param controllerAddress the address of the controller who wants to set the data key.
     * @param controllerPermissions the permissions of the controller address.
     * @param inputDataKeys an array of data keys to set on the `controlledContract`.
     * @param inputDataValues an array of data values to set for the `inputDataKeys`.
     */
    function _verifyCanSetData(
        address controlledContract,
        address controllerAddress,
        bytes32 controllerPermissions,
        bytes32[] memory inputDataKeys,
        bytes[] memory inputDataValues
    ) internal view virtual {
        bool isSettingERC725YKeys;
        bool[] memory validatedInputDataKeys = new bool[](inputDataKeys.length);

        bytes32 requiredPermission;

        uint256 ii;
        do {
            requiredPermission = _getPermissionRequiredToSetDataKey(
                controlledContract,
                inputDataKeys[ii],
                inputDataValues[ii]
            );

            if (requiredPermission == _PERMISSION_SETDATA) {
                isSettingERC725YKeys = true;
            } else {
                // CHECK the required permissions if setting LSP6 permissions, LSP1 Delegate or LSP17 Extensions.
                _requirePermissions(controllerAddress, controllerPermissions, requiredPermission);
                validatedInputDataKeys[ii] = true;
            }

            ii = GasLib.uncheckedIncrement(ii);
        } while (ii < inputDataKeys.length);

        // CHECK if allowed to set one (or multiple) ERC725Y Data Keys
        if (isSettingERC725YKeys) {
            // Skip if caller has SUPER permissions
            if (controllerPermissions.hasPermission(_PERMISSION_SUPER_SETDATA)) return;

            _requirePermissions(controllerAddress, controllerPermissions, _PERMISSION_SETDATA);

            _verifyAllowedERC725YDataKeys(
                controllerAddress,
                inputDataKeys,
                ERC725Y(controlledContract).getAllowedERC725YDataKeysFor(controllerAddress),
                validatedInputDataKeys
            );
        }
    }

    /**
     * @dev retrieve the permission required based on the data key to be set on the `controlledContract`.
     * @param controlledContract the address of the ERC725Y contract where the data key is verified.
     * @param inputDataKey the data key to set on the `controlledContract`. Can be related to LSP6 Permissions, LSP1 Delegate or LSP17 Extensions.
     * @param inputDataValue the data value to set for the `inputDataKey`.
     * @return the permission required to set the `inputDataKey` on the `controlledContract`.
     */
    function _getPermissionRequiredToSetDataKey(
        address controlledContract,
        bytes32 inputDataKey,
        bytes memory inputDataValue
    ) internal view virtual returns (bytes32) {
        // AddressPermissions[] or AddressPermissions[index]
        if (bytes16(inputDataKey) == _LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX) {
            return
                _getPermissionToSetPermissionsArray(
                    controlledContract,
                    inputDataKey,
                    inputDataValue
                );

            // AddressPermissions:...
        } else if (bytes6(inputDataKey) == _LSP6KEY_ADDRESSPERMISSIONS_PREFIX) {
            // AddressPermissions:Permissions:<address>
            if (bytes12(inputDataKey) == _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX) {
                return _getPermissionToSetControllerPermissions(controlledContract, inputDataKey);

                // AddressPermissions:AllowedCalls:<address>
            } else if (bytes12(inputDataKey) == _LSP6KEY_ADDRESSPERMISSIONS_ALLOWEDCALLS_PREFIX) {
                return
                    _getPermissionToSetAllowedCalls(
                        controlledContract,
                        inputDataKey,
                        inputDataValue
                    );

                // AddressPermissions:AllowedERC725YKeys:<address>
            } else if (
                bytes12(inputDataKey) == _LSP6KEY_ADDRESSPERMISSIONS_AllowedERC725YDataKeys_PREFIX
            ) {
                return
                    _getPermissionToSetAllowedERC725YDataKeys(
                        controlledContract,
                        inputDataKey,
                        inputDataValue
                    );

                // if the first 6 bytes of the input data key are "AddressPermissions:..." but did not match
                // with anything above, this is not a standard LSP6 permission data key so we revert.
            } else {
                /**
                 * @dev more permissions types starting with `AddressPermissions:...` can be implemented by overriding this function.
                 *
                 *      // AddressPermissions:MyCustomPermissions:<address>
                 *      bytes12 CUSTOM_PERMISSION_PREFIX = 0x4b80742de2bf9e659ba40000
                 *
                 *      if (bytes12(dataKey) == CUSTOM_PERMISSION_PREFIX) {
                 *          // custom logic
                 *      }
                 *
                 *      super._getPermissionRequiredToSetDataKey(...)
                 */
                revert NotRecognisedPermissionKey(inputDataKey);
            }

            // LSP1UniversalReceiverDelegate or LSP1UniversalReceiverDelegate:<typeId>
        } else if (
            inputDataKey == _LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY ||
            bytes12(inputDataKey) == _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX
        ) {
            return _getPermissionToSetLSP1Delegate(controlledContract, inputDataKey);

            // LSP17Extension:<bytes4>
        } else if (bytes12(inputDataKey) == _LSP17_EXTENSION_PREFIX) {
            return _getPermissionToSetLSP17Extension(controlledContract, inputDataKey);
        } else {
            return _PERMISSION_SETDATA;
        }
    }

    /**
     * @dev retrieve the permission required to update the `AddressPermissions[]` array data key defined in LSP6.
     * @param controlledContract the address of the ERC725Y contract where the data key is verified.
     * @param inputDataKey either `AddressPermissions[]` (array length) or `AddressPermissions[index]` (array index)
     * @param inputDataValue the updated value for the `inputDataKey`. MUST be:
     *  - a `uint256` for `AddressPermissions[]` (array length)
     *  - an `address` or `0x` for `AddressPermissions[index]` (array entry).
     *
     * @return either ADD or CHANGE PERMISSIONS.
     */
    function _getPermissionToSetPermissionsArray(
        address controlledContract,
        bytes32 inputDataKey,
        bytes memory inputDataValue
    ) internal view virtual returns (bytes32) {
        bytes memory currentValue = ERC725Y(controlledContract).getData(inputDataKey);

        // AddressPermissions[] -> array length
        if (inputDataKey == _LSP6KEY_ADDRESSPERMISSIONS_ARRAY) {
            uint128 newLength = uint128(bytes16(inputDataValue));

            return
                newLength > uint128(bytes16(currentValue))
                    ? _PERMISSION_ADDCONTROLLER
                    : _PERMISSION_EDITPERMISSIONS;
        }

        // AddressPermissions[index] -> array index

        // CHECK that we either ADD an address (20 bytes long) or REMOVE an address (0x)
        if (inputDataValue.length != 0 && inputDataValue.length != 20) {
            revert AddressPermissionArrayIndexValueNotAnAddress(inputDataKey, inputDataValue);
        }

        return currentValue.length == 0 ? _PERMISSION_ADDCONTROLLER : _PERMISSION_EDITPERMISSIONS;
    }

    /**
     * @dev retrieve the permission required to set permissions for a controller address.
     * @param controlledContract the address of the ERC725Y contract where the data key is verified.
     * @param inputPermissionDataKey `AddressPermissions:Permissions:<controller-address>`.
     * @return either ADD or CHANGE PERMISSIONS.
     */
    function _getPermissionToSetControllerPermissions(
        address controlledContract,
        bytes32 inputPermissionDataKey
    ) internal view virtual returns (bytes32) {
        return
            // if there is nothing stored under the data key, we are trying to ADD a new controller.
            // if there are already some permissions set under the data key, we are trying to CHANGE the permissions of a controller.
            bytes32(ERC725Y(controlledContract).getData(inputPermissionDataKey)) == bytes32(0)
                ? _PERMISSION_ADDCONTROLLER
                : _PERMISSION_EDITPERMISSIONS;
    }

    /**
     * @dev retrieve the permission required to set some AllowedCalls for a controller.
     * @param controlledContract the address of the ERC725Y contract where the data key is verified.
     * @param dataKey `AddressPermissions:AllowedCalls:<controller-address>`.
     * @param dataValue the updated value for the `dataKey`. MUST be a bytes28[CompactBytesArray] of Allowed Calls.
     * @return either ADD or CHANGE PERMISSIONS.
     */
    function _getPermissionToSetAllowedCalls(
        address controlledContract,
        bytes32 dataKey,
        bytes memory dataValue
    ) internal view virtual returns (bytes32) {
        if (!LSP6Utils.isCompactBytesArrayOfAllowedCalls(dataValue)) {
            revert InvalidEncodedAllowedCalls(dataValue);
        }

        // if there is nothing stored under the Allowed Calls of the controller,
        // we are trying to ADD a list of restricted calls (standards + address + function selector)
        //
        // if there are already some data set under the Allowed Calls of the controller,
        // we are trying to CHANGE (= edit) these restrictions.
        return
            ERC725Y(controlledContract).getData(dataKey).length == 0
                ? _PERMISSION_ADDCONTROLLER
                : _PERMISSION_EDITPERMISSIONS;
    }

    /**
     * @dev retrieve the permission required to set some AllowedCalls for a controller.
     * @param controlledContract the address of the ERC725Y contract where the data key is verified.
     * @param dataKey  or `AddressPermissions:AllowedERC725YDataKeys:<controller-address>`.
     * @param dataValue the updated value for the `dataKey`. MUST be a bytes[CompactBytesArray] of Allowed ERC725Y Data Keys.
     * @return either ADD or CHANGE PERMISSIONS.
     */
    function _getPermissionToSetAllowedERC725YDataKeys(
        address controlledContract,
        bytes32 dataKey,
        bytes memory dataValue
    ) internal view returns (bytes32) {
        if (!LSP6Utils.isCompactBytesArrayOfAllowedERC725YDataKeys(dataValue)) {
            revert InvalidEncodedAllowedERC725YDataKeys(dataValue);
        }

        // if there is nothing stored under the Allowed ERC725Y Data Keys of the controller,
        // we are trying to ADD a list of restricted ERC725Y Data Keys.
        //
        // if there are already some data set under the Allowed ERC725Y Data Keys of the controller,
        // we are trying to CHANGE (= edit) these restricted ERC725Y data keys.
        return
            ERC725Y(controlledContract).getData(dataKey).length == 0
                ? _PERMISSION_ADDCONTROLLER
                : _PERMISSION_EDITPERMISSIONS;
    }

    /**
     * @dev retrieve the permission required to either add or change the address
     * of a LSP1 Universal Receiver Delegate stored under a specific LSP1 data key.
     * @param controlledContract the address of the ERC725Y contract where the data key is verified.
     * @param lsp1DelegateDataKey either the data key for the default `LSP1UniversalReceiverDelegate`,
     * or a data key for a specific `LSP1UniversalReceiverDelegate:<typeId>`, starting with `_LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX`.
     * @return either ADD or CHANGE UNIVERSALRECEIVERDELEGATE.
     */
    function _getPermissionToSetLSP1Delegate(
        address controlledContract,
        bytes32 lsp1DelegateDataKey
    ) internal view virtual returns (bytes32) {
        return
            ERC725Y(controlledContract).getData(lsp1DelegateDataKey).length == 0
                ? _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE
                : _PERMISSION_CHANGEUNIVERSALRECEIVERDELEGATE;
    }

    /**
     * @dev Verify if `controller` has the required permissions to either add or change the address
     * of an LSP0 Extension stored under a specific LSP17Extension data key
     * @param controlledContract the address of the ERC725Y contract where the data key is verified.
     * @param lsp17ExtensionDataKey the dataKey to set with `_LSP17_EXTENSION_PREFIX` as prefix.
     */
    function _getPermissionToSetLSP17Extension(
        address controlledContract,
        bytes32 lsp17ExtensionDataKey
    ) internal view virtual returns (bytes32) {
        return
            ERC725Y(controlledContract).getData(lsp17ExtensionDataKey).length == 0
                ? _PERMISSION_ADDEXTENSIONS
                : _PERMISSION_CHANGEEXTENSIONS;
    }

    /**
     * @dev Verify if the `inputKey` is present in the list of `allowedERC725KeysCompacted` for the `controllerAddress`.
     * @param controllerAddress the address of the controller.
     * @param inputDataKey the data key to verify against the allowed ERC725Y Data Keys for the `controllerAddress`.
     * @param allowedERC725YDataKeysCompacted a CompactBytesArray of allowed ERC725Y Data Keys for the `controllerAddress`.
     */
    function _verifyAllowedERC725YSingleKey(
        address controllerAddress,
        bytes32 inputDataKey,
        bytes memory allowedERC725YDataKeysCompacted
    ) internal pure virtual {
        if (allowedERC725YDataKeysCompacted.length == 0)
            revert NoERC725YDataKeysAllowed(controllerAddress);

        /**
         * The pointer will always land on the length of each bytes value:
         *
         * ↓↓
         * 03 a00000
         * 05 fff83a0011
         * 20 aa0000000000000000000000000000000000000000000000000000000000cafe
         * 12 bb000000000000000000000000000000beef
         * 19 cc00000000000000000000000000000000000000000000deed
         * ↑↑
         *
         */
        uint256 pointer;

        // information extracted from each Allowed ERC725Y Data Key.
        uint256 length;
        bytes32 allowedKey;
        bytes32 mask;

        /**
         * iterate over each data key and update the `pointer` variable with the index where to find the length of each data key.
         *
         * 0x 03 a00000 03 fff83a 20 aa00...00cafe
         *    ↑↑        ↑↑        ↑↑
         *  first  |  second  |  third
         *  length |  length  |  length
         */
        while (pointer < allowedERC725YDataKeysCompacted.length) {
            // save the length of the allowed data key to calculate the `mask`.
            length = uint16(
                bytes2(
                    abi.encodePacked(
                        allowedERC725YDataKeysCompacted[pointer],
                        allowedERC725YDataKeysCompacted[pointer + 1]
                    )
                )
            );

            /**
             * The bitmask discard the last `32 - length` bytes of the input data key via ANDing &
             * It is used to compare only the relevant parts of each input data key against dynamic allowed data keys.
             *
             * E.g.:
             *
             * allowed data key = 0xa00000
             *
             *                compare this part
             *                    vvvvvv
             * input data key = 0xa00000cafecafecafecafecafecafecafe000000000000000000000011223344
             *
             *             &                              discard this part
             *                       vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
             *           mask = 0xffffff0000000000000000000000000000000000000000000000000000000000
             */
            mask =
                bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) <<
                (8 * (32 - length));

            /*
             * transform the allowed data key situated from `pointer + 1` until `pointer + 1 + length` to a bytes32 value.
             * E.g. 0xfff83a -> 0xfff83a0000000000000000000000000000000000000000000000000000000000
             */
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // the first 32 bytes word in memory (where allowedERC725YDataKeysCompacted is stored)
                // correspond to the total number of bytes in `allowedERC725YDataKeysCompacted`
                let offset := add(add(pointer, 2), 32)
                let memoryAt := mload(add(allowedERC725YDataKeysCompacted, offset))
                // MLOAD loads 32 bytes word, so we need to keep only the `length` number of bytes that makes up the allowed data key.
                allowedKey := and(memoryAt, mask)
            }

            // voila you found the key ;)
            if (allowedKey == (inputDataKey & mask)) return;

            // move the pointer to the index of the next allowed data key
            unchecked {
                pointer = pointer + (length + 2);
            }
        }

        revert NotAllowedERC725YDataKey(controllerAddress, inputDataKey);
    }

    /**
     * @dev Verify if all the `inputDataKeys` are present in the list of `allowedERC725KeysCompacted` of the `controllerAddress`.
     * @param controllerAddress the address of the controller.
     * @param inputDataKeys the data keys to verify against the allowed ERC725Y Data Keys of the `controllerAddress`.
     * @param allowedERC725YDataKeysCompacted a CompactBytesArray of allowed ERC725Y Data Keys of the `controllerAddress`.
     * @param validatedInputKeys an array of booleans to store the result of the verification of each data keys checked.
     */
    function _verifyAllowedERC725YDataKeys(
        address controllerAddress,
        bytes32[] memory inputDataKeys,
        bytes memory allowedERC725YDataKeysCompacted,
        bool[] memory validatedInputKeys
    ) internal pure virtual {
        if (allowedERC725YDataKeysCompacted.length == 0)
            revert NoERC725YDataKeysAllowed(controllerAddress);

        uint256 allowedKeysFound;

        // cache the input data keys from the start
        uint256 inputKeysLength = inputDataKeys.length;

        /**
         * The pointer will always land on the length of each bytes value:
         *
         * ↓↓
         * 03 a00000
         * 05 fff83a0011
         * 20 aa0000000000000000000000000000000000000000000000000000000000cafe
         * 12 bb000000000000000000000000000000beef
         * 19 cc00000000000000000000000000000000000000000000deed
         * ↑↑
         *
         */
        uint256 pointer;

        // information extracted from each Allowed ERC725Y Data Key.
        uint256 length;
        bytes32 allowedKey;
        bytes32 mask;

        /**
         * iterate over each data key and update the `pointer` variable with the index where to find the length of each data key.
         *
         * 0x 03 a00000 03 fff83a 20 aa00...00cafe
         *    ↑↑        ↑↑        ↑↑
         *  first  |  second  |  third
         *  length |  length  |  length
         */
        while (pointer < allowedERC725YDataKeysCompacted.length) {
            // save the length of the allowed data key to calculate the `mask`.
            length = uint16(
                bytes2(
                    abi.encodePacked(
                        allowedERC725YDataKeysCompacted[pointer],
                        allowedERC725YDataKeysCompacted[pointer + 1]
                    )
                )
            );

            /**
             * The bitmask discard the last `32 - length` bytes of the input data key via ANDing &
             * It is used to compare only the relevant parts of each input data key against dynamic allowed data keys.
             *
             * E.g.:
             *
             * allowed data key = 0xa00000
             *
             *                compare this part
             *                    vvvvvv
             * input data key = 0xa00000cafecafecafecafecafecafecafe000000000000000000000011223344
             *
             *             &                              discard this part
             *                       vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
             *           mask = 0xffffff0000000000000000000000000000000000000000000000000000000000
             */
            mask =
                bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) <<
                (8 * (32 - length));

            /*
             * transform the allowed data key situated from `pointer + 1` until `pointer + 1 + length` to a bytes32 value.
             * E.g. 0xfff83a -> 0xfff83a0000000000000000000000000000000000000000000000000000000000
             */
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // the first 32 bytes word in memory (where allowedERC725YDataKeysCompacted is stored)
                // correspond to the length of allowedERC725YDataKeysCompacted (= total number of bytes)
                let offset := add(add(pointer, 2), 32)
                let memoryAt := mload(add(allowedERC725YDataKeysCompacted, offset))
                allowedKey := and(memoryAt, mask)
            }

            /**
             * Iterate over the `inputDataKeys` to check them against the allowed data keys.
             * This until we have validated them all.
             */
            for (uint256 ii; ii < inputKeysLength; ii = GasLib.uncheckedIncrement(ii)) {
                // if the input data key has been marked as allowed previously,
                // SKIP it and move to the next input data key.
                if (validatedInputKeys[ii]) continue;

                // CHECK if the input data key is allowed.
                if ((inputDataKeys[ii] & mask) == allowedKey) {
                    // if the input data key is allowed, mark it as allowed
                    // and increment the number of allowed keys found.
                    validatedInputKeys[ii] = true;
                    allowedKeysFound = GasLib.uncheckedIncrement(allowedKeysFound);

                    // Continue checking until all the inputKeys` have been found.
                    if (allowedKeysFound == inputKeysLength) return;
                }
            }

            // Move the pointer to the next AllowedERC725YKey
            unchecked {
                pointer = pointer + (length + 2);
            }
        }

        // if we did not find all the input data keys, search for the first not allowed data key to revert.
        for (uint256 jj; jj < inputKeysLength; jj = GasLib.uncheckedIncrement(jj)) {
            if (!validatedInputKeys[jj]) {
                revert NotAllowedERC725YDataKey(controllerAddress, inputDataKeys[jj]);
            }
        }
    }

    /**
     * @dev revert if `controller`'s `addressPermissions` doesn't contain `permissionsRequired`
     * @param controller the caller address
     * @param addressPermissions the caller's permissions BitArray
     * @param permissionRequired the required permission
     */
    function _requirePermissions(
        address controller,
        bytes32 addressPermissions,
        bytes32 permissionRequired
    ) internal pure virtual {
        if (!LSP6Utils.hasPermission(addressPermissions, permissionRequired)) {
            string memory permissionErrorString = LSP6Utils.getPermissionName(permissionRequired);
            revert NotAuthorised(controller, permissionErrorString);
        }
    }
}