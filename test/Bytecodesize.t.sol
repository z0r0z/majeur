// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Moloch, Summoner} from "../src/Moloch.sol";
import {Renderer} from "../src/Renderer.sol"; // only needed to ensure artifact is built

contract BytecodeSizeTest is Test {
    // 24 KB runtime size cap (your custom / L2-style limit)
    uint256 constant MAX_RUNTIME_SIZE = 24_576;

    // 48 KB initcode cap from EIP-3860 (protocol limit)
    uint256 constant MAX_INITCODE_SIZE = 49_152;

    /*//////////////////////////////////////////////////////////////
                           MOLOCH
    //////////////////////////////////////////////////////////////*/

    function testMolochRuntimeSize() public view {
        uint256 size = getRuntimeSize("Moloch");

        console.log("Checking Moloch RUNTIME size...");
        console.log("Size:", size, "bytes");

        assertLe(
            size,
            MAX_RUNTIME_SIZE,
            string.concat(
                "Moloch RUNTIME exceeds max size: ",
                vm.toString(size),
                " > ",
                vm.toString(MAX_RUNTIME_SIZE)
            )
        );
    }

    function testMolochInitCodeSize() public view {
        uint256 size = getInitCodeSize("Moloch");

        console.log("Checking Moloch INITCODE size...");
        console.log("Size:", size, "bytes");

        assertLe(
            size,
            MAX_INITCODE_SIZE,
            string.concat(
                "Moloch initCode exceeds EIP-3860 limit: ",
                vm.toString(size),
                " > ",
                vm.toString(MAX_INITCODE_SIZE)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                           SUMMONER
    //////////////////////////////////////////////////////////////*/

    function testSummonerRuntimeSize() public view {
        uint256 size = getRuntimeSize("Summoner");

        console.log("Checking Summoner RUNTIME size...");
        console.log("Size:", size, "bytes");

        assertLe(
            size,
            MAX_RUNTIME_SIZE,
            string.concat(
                "Summoner RUNTIME exceeds max size: ",
                vm.toString(size),
                " > ",
                vm.toString(MAX_RUNTIME_SIZE)
            )
        );
    }

    function testSummonerInitCodeSize() public view {
        uint256 size = getInitCodeSize("Summoner");

        console.log("Checking Summoner INITCODE size...");
        console.log("Size:", size, "bytes");

        assertLe(
            size,
            MAX_INITCODE_SIZE,
            string.concat(
                "Summoner initCode exceeds EIP-3860 limit: ",
                vm.toString(size),
                " > ",
                vm.toString(MAX_INITCODE_SIZE)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                           RENDERER
    //////////////////////////////////////////////////////////////*/

    function testRendererRuntimeSize() public view {
        // Renderer is defined in src/Renderer.sol, artifact: out/Renderer.sol/Renderer.json
        uint256 size = getRuntimeSizeFromFile("Renderer.sol", "Renderer");

        console.log("Checking Renderer RUNTIME size...");
        console.log("Size:", size, "bytes");

        assertLe(
            size,
            MAX_RUNTIME_SIZE,
            string.concat(
                "Renderer RUNTIME exceeds max size: ",
                vm.toString(size),
                " > ",
                vm.toString(MAX_RUNTIME_SIZE)
            )
        );
    }

    function testRendererInitCodeSize() public view {
        uint256 size = getInitCodeSizeFromFile("Renderer.sol", "Renderer");

        console.log("Checking Renderer INITCODE size...");
        console.log("Size:", size, "bytes");

        assertLe(
            size,
            MAX_INITCODE_SIZE,
            string.concat(
                "Renderer initCode exceeds EIP-3860 limit: ",
                vm.toString(size),
                " > ",
                vm.toString(MAX_INITCODE_SIZE)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                           HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev initcode = creation bytecode (what CREATE/CREATE2 sees)
    function getInitCodeSize(string memory contractName) internal view returns (uint256) {
        // default: contracts defined in src/Moloch.sol
        bytes memory bytecode = getArtifactBytes(contractName, ".bytecode.object");
        return bytecode.length;
    }

    /// @dev runtime code = deployed bytecode (what EXTCODESIZE sees)
    function getRuntimeSize(string memory contractName) internal view returns (uint256) {
        // default: contracts defined in src/Moloch.sol
        bytes memory bytecode = getArtifactBytes(contractName, ".deployedBytecode.object");
        return bytecode.length;
    }

    /// @dev initcode size for a contract defined in a specific source file
    function getInitCodeSizeFromFile(string memory sourceFile, string memory contractName)
        internal
        view
        returns (uint256)
    {
        bytes memory bytecode = getArtifactBytes(sourceFile, contractName, ".bytecode.object");
        return bytecode.length;
    }

    /// @dev runtime size for a contract defined in a specific source file
    function getRuntimeSizeFromFile(string memory sourceFile, string memory contractName)
        internal
        view
        returns (uint256)
    {
        bytes memory bytecode =
            getArtifactBytes(sourceFile, contractName, ".deployedBytecode.object");
        return bytecode.length;
    }

    /// @dev Default artifact lookup for contracts in src/Moloch.sol
    function getArtifactBytes(string memory contractName, string memory field)
        internal
        view
        returns (bytes memory)
    {
        // hard-coded source file "Moloch.sol" for Moloch & Summoner
        return getArtifactBytes("Moloch.sol", contractName, field);
    }

    /// @dev Generic artifact lookup for any source file + contract
    function getArtifactBytes(
        string memory sourceFile,
        string memory contractName,
        string memory field
    ) internal view returns (bytes memory) {
        string memory artifactPath = string.concat("out/", sourceFile, "/", contractName, ".json");

        string memory artifact = vm.readFile(artifactPath);
        return vm.parseJsonBytes(artifact, field);
    }

    // Optional helper if you ever want to check a deployed instance:
    function getDeployedSize(address target) public view returns (uint256 size) {
        assembly {
            size := extcodesize(target)
        }
    }
}
