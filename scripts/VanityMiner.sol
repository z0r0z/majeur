// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "@forge/Script.sol";

/// @title VanityMiner
/// @notice Mine CREATE2 salts for vanity module addresses deployed via SafeSummoner.create2Deploy.
/// @dev Usage:
///   1. Set env vars:
///        DEPLOYER    — SafeSummoner address (the CREATE2 deployer)
///        INIT_CODE   — Full creation bytecode of the module (hex, no 0x prefix OK)
///        PREFIX      — Desired hex prefix for the address (e.g. "0000" for 0x0000...)
///        CALLER      — (optional) msg.sender, mixed into salt for front-run protection
///        OFFSET      — (optional) start nonce (default 0)
///        BATCH       — (optional) salts to try per run (default 1_000_000)
///
///   2. Run:
///        forge script scripts/VanityMiner.sol -vvv
///
///   The script prints matching salt(s) and predicted address(es).
///   For leading-zero vanity (gas-efficient addresses), use PREFIX=0000 or similar.
contract VanityMiner is Script {
    function run() public view {
        address deployer = vm.envAddress("DEPLOYER");
        bytes memory initCode = vm.envBytes("INIT_CODE");
        string memory prefix = vm.envOr("PREFIX", string("0000"));
        address caller = vm.envOr("CALLER", address(0));
        uint256 offset = vm.envOr("OFFSET", uint256(0));
        uint256 batch = vm.envOr("BATCH", uint256(1_000_000));

        bytes32 initCodeHash = keccak256(initCode);
        bytes memory target = _hexToBytes(prefix);
        uint256 targetLen = target.length;

        console.log("=== VanityMiner ===");
        console.log("Deployer:      ", deployer);
        console.log("InitCodeHash:  ");
        console.logBytes32(initCodeHash);
        console.log("Prefix:         0x%s", prefix);
        if (caller != address(0)) console.log("Caller:        ", caller);
        console.log("Searching %d salts from offset %d ...", batch, offset);
        console.log("");

        uint256 found;
        for (uint256 i = offset; i < offset + batch; i++) {
            // Mix caller into salt so nobody else can front-run your deployment
            bytes32 salt = caller == address(0)
                ? bytes32(i)
                : keccak256(abi.encodePacked(caller, i));

            address predicted = _predict(deployer, salt, initCodeHash);
            if (_matchesPrefix(predicted, target, targetLen)) {
                found++;
                console.log("MATCH #%d", found);
                console.log("  nonce:   %d", i);
                console.log("  salt:    ");
                console.logBytes32(salt);
                console.log("  address: ", predicted);
                console.log("");
            }
        }

        if (found == 0) {
            console.log("No matches found. Try increasing BATCH or shifting OFFSET.");
        } else {
            console.log("Found %d match(es).", found);
        }
    }

    function _predict(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash))
                )
            )
        );
    }

    /// @dev Check if the leading bytes of an address match `target`.
    function _matchesPrefix(address addr, bytes memory target, uint256 len)
        internal
        pure
        returns (bool)
    {
        bytes20 raw = bytes20(addr);
        for (uint256 i; i < len; i++) {
            if (raw[i] != target[i]) return false;
        }
        return true;
    }

    /// @dev Convert a hex string (no 0x prefix) to bytes.
    ///      E.g. "0000" → 0x0000, "dead" → 0xdead.
    ///      Must be even length.
    function _hexToBytes(string memory hex_) internal pure returns (bytes memory) {
        bytes memory h = bytes(hex_);
        require(h.length % 2 == 0, "hex prefix must be even length");
        bytes memory result = new bytes(h.length / 2);
        for (uint256 i; i < h.length; i += 2) {
            result[i / 2] = bytes1(_hexCharToNibble(h[i]) << 4 | _hexCharToNibble(h[i + 1]));
        }
        return result;
    }

    function _hexCharToNibble(bytes1 c) internal pure returns (uint8) {
        if (c >= "0" && c <= "9") return uint8(c) - 48;
        if (c >= "a" && c <= "f") return uint8(c) - 87;
        if (c >= "A" && c <= "F") return uint8(c) - 55;
        revert("invalid hex char");
    }
}
