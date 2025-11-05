// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Cell Wallet (Cell/CellWall.eth)
/// @notice 2-of-2 smart contract wallet,
/// with a soft guardian 2-of-3 role too.
contract Cell {
    error Signed();
    error Expired();
    error BadSign();
    error BadOwner();
    error WrongLen();
    error NotOwner();
    error NotApprover();
    error AlreadyApproved();

    address[3] public owners;
    string[] public messages;

    mapping(bytes32 hash => address owner) public approved;
    mapping(address signer => mapping(bytes32 hash => bool)) public usedSigForHash;
    mapping(address token => mapping(address spender => uint256)) public allowance;
    mapping(bytes32 hash => mapping(address spender => uint256 count)) public permits;

    address immutable CREATOR;
    uint256 immutable INITIAL_CHAIN_ID;
    bytes32 immutable INITIAL_DOMAIN_SEPARATOR;

    bytes32 constant SIGN_BATCH_TYPEHASH = keccak256("SignBatch(bytes32 hash,uint256 deadline)");

    event OwnershipTransferred(address indexed from, address indexed to);

    /// @dev Construct 2/2 Cell with sorted owners and optional guardian.
    constructor(address owner0, address owner1, address guardian) payable {
        require(owner0 != address(0) && owner1 != address(0) && owner0 != owner1, BadOwner());
        (owner0, owner1) = owner1 < owner0 ? (owner1, owner0) : (owner0, owner1);
        emit OwnershipTransferred(owners[0] = owner0, owners[1] = owner1);

        CREATOR = msg.sender;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();

        if (guardian != address(0)) emit OwnershipTransferred(address(this), owners[2] = guardian);
    }

    /// @dev Execute Cell call to contract or EOA.
    function execute(address to, uint256 value, bytes calldata data, bytes32 nonce)
        public
        payable
        returns (bool first, bool ok, bytes memory retData)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(this.execute.selector, to, value, keccak256(data), nonce)
        );

        address _approved = approved[hash];
        first = _approved == address(0);
        if (!first) require(msg.sender != _approved, AlreadyApproved());
        require(
            msg.sender == owners[0] || msg.sender == owners[1] || msg.sender == owners[2],
            NotOwner()
        );

        if (first) {
            approved[hash] = msg.sender;
            return (true, true, "");
        }

        delete approved[hash];
        (ok, retData) = to.call{value: value}(data);
        if (!ok) _revertWith(retData);
    }

    /// @dev Execute batch of Cell calls to contracts or EOAs.
    function batchExecute(
        address[] calldata tos,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 nonce
    ) public payable returns (bool first, bool[] memory oks, bytes[] memory retDatas) {
        uint256 len = tos.length;
        require(len == values.length && len == datas.length, WrongLen());

        bytes32 hash = _hashBatch(tos, values, datas, nonce);

        address _approved = approved[hash];
        first = _approved == address(0);
        if (!first) require(msg.sender != _approved, AlreadyApproved());
        require(
            msg.sender == owners[0] || msg.sender == owners[1] || msg.sender == owners[2],
            NotOwner()
        );

        if (first) {
            approved[hash] = msg.sender;
            return (true, new bool[](0), new bytes[](0));
        }

        oks = new bool[](len);
        retDatas = new bytes[](len);

        delete approved[hash];
        for (uint256 i; i != len; ++i) {
            (oks[i], retDatas[i]) = tos[i].call{value: values[i]}(datas[i]);
            if (!oks[i]) _revertWith(retDatas[i]);
        }
    }

    /// @dev Execute batch of Cell calls to contracts or EOAs via EIP-712-signed approval.
    function batchExecuteWithSig(
        address[] calldata tos,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable returns (bool first, bool[] memory oks, bytes[] memory retDatas) {
        uint256 len = tos.length;
        require(len == values.length && len == datas.length, WrongLen());
        require(deadline >= block.timestamp, Expired());

        bytes32 hash = _hashBatch(tos, values, datas, nonce);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(SIGN_BATCH_TYPEHASH, hash, deadline))
            )
        );

        if (v < 27) v += 27;
        require(v == 27 || v == 28, BadSign());
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert BadSign();
        }
        address signer = ecrecover(digest, v, r, s);
        require(
            signer != address(0)
                && (signer == owners[0] || signer == owners[1] || signer == owners[2]),
            NotOwner()
        );

        address _approved = approved[hash];
        first = (_approved == address(0));
        if (first) {
            if (usedSigForHash[signer][hash]) revert Signed();
            usedSigForHash[signer][hash] = true;
            approved[hash] = signer;
            return (true, new bool[](0), new bytes[](0));
        }

        require(signer != _approved, AlreadyApproved());
        delete approved[hash];

        if (usedSigForHash[signer][hash]) revert Signed();
        usedSigForHash[signer][hash] = true;

        oks = new bool[](len);
        retDatas = new bytes[](len);

        for (uint256 i; i != len; ++i) {
            (oks[i], retDatas[i]) = tos[i].call{value: values[i]}(datas[i]);
            if (!oks[i]) _revertWith(retDatas[i]);
        }
    }

    /// @dev Batch hash helper.
    function _hashBatch(
        address[] calldata tos,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 nonce
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                this.batchExecute.selector,
                keccak256(abi.encode(tos)),
                keccak256(abi.encode(values)),
                keccak256(abi.encode(datas)),
                nonce
            )
        );
    }

    /// @dev Delegate Cell call execution to contract.
    function delegateExecute(address to, bytes calldata data, bytes32 nonce)
        public
        payable
        returns (bool first, bool ok, bytes memory retData)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(this.delegateExecute.selector, to, keccak256(data), nonce)
        );
        address _approved = approved[hash];
        first = _approved == address(0);
        if (!first) require(msg.sender != _approved, AlreadyApproved());
        require(
            msg.sender == owners[0] || msg.sender == owners[1] || msg.sender == owners[2],
            NotOwner()
        );

        if (first) {
            approved[hash] = msg.sender;
            return (true, true, "");
        }

        delete approved[hash];
        (ok, retData) = to.delegatecall(data);
        if (!ok) _revertWith(retData);
    }

    /// @dev Cancel Cell execution from approving owner.
    function cancel(bytes32 hash) public payable {
        require(msg.sender == approved[hash], NotApprover());
        delete approved[hash];
    }

    /// @dev Spend permit counter for Cell call execution by owner.
    function spendPermit(address to, uint256 value, bytes calldata data)
        public
        payable
        returns (bool ok, bytes memory retData)
    {
        bytes32 hash =
            keccak256(abi.encodePacked(this.execute.selector, to, value, keccak256(data)));

        --permits[hash][msg.sender];

        (ok, retData) = to.call{value: value}(data);
        if (!ok) _revertWith(retData);
    }

    /// @dev Set permit counter for Cell call execution to spender. Can be zeroed out.
    function setPermit(
        address spender,
        uint256 count,
        address to,
        uint256 value,
        bytes calldata data
    ) public payable returns (bool is0, bool byOwner) {
        is0 = (msg.sender == owners[0]);
        require(
            is0 || msg.sender == owners[1] || msg.sender == address(this) || msg.sender == CREATOR,
            NotOwner()
        );
        bytes32 hash =
            keccak256(abi.encodePacked(this.execute.selector, to, value, keccak256(data)));
        if (msg.sender != address(this) && msg.sender != CREATOR) byOwner = true;
        permits[hash][byOwner ? owners[is0 ? 1 : 0] : spender] = count;
    }

    /// @dev Spend allowance set by owner.
    function spendAllowance(address token, uint256 amount) public payable {
        allowance[token][msg.sender] -= amount;
        if (token == address(0)) {
            safeTransferETH(msg.sender, amount);
        } else {
            safeTransfer(token, msg.sender, amount);
        }
    }

    /// @dev Set allowance for other owner by owner or for spender.
    function setAllowance(address spender, address token, uint256 amount)
        public
        payable
        returns (bool is0, bool byOwner)
    {
        is0 = (msg.sender == owners[0]);
        require(
            is0 || msg.sender == owners[1] || msg.sender == address(this) || msg.sender == CREATOR,
            NotOwner()
        );
        if (msg.sender != address(this) && msg.sender != CREATOR) byOwner = true;
        allowance[token][byOwner ? owners[is0 ? 1 : 0] : spender] = amount;
    }

    /// @dev Pull token from allowance preset by owner.
    function pullToken(address token, address owner, uint256 amount) public payable {
        require(
            msg.sender == owners[0] || msg.sender == owners[1] || msg.sender == address(this)
                || msg.sender == CREATOR,
            NotOwner()
        );
        safeTransferFrom(token, owner, amount);
    }

    /// @dev Approve token allowance to another spender by owner.
    function approveToken(address token, address spender, uint256 amount)
        public
        payable
        returns (bool is0, bool byOwner)
    {
        is0 = (msg.sender == owners[0]);
        require(
            is0 || msg.sender == owners[1] || msg.sender == address(this) || msg.sender == CREATOR,
            NotOwner()
        );
        if (msg.sender != address(this) && msg.sender != CREATOR) byOwner = true;
        safeApprove(token, byOwner ? owners[is0 ? 1 : 0] : spender, amount);
    }

    /// @dev Transfer 1/2 Cell sorted ownership slot to new owner.
    function transferOwnership(address to) public payable returns (bool is0) {
        address o0 = owners[0];
        address o1 = owners[1];

        is0 = (msg.sender == o0);
        if (!is0 && msg.sender != o1) revert NotOwner();

        if (to == address(0) || to == msg.sender) revert BadOwner();
        if (to == (is0 ? o1 : o0)) revert BadOwner();

        if (is0 ? (to > o1) : (to < o0)) {
            if (is0) {
                owners[1] = to;
                owners[0] = o1;
            } else {
                owners[0] = to;
                owners[1] = o0;
            }
        } else {
            if (is0) owners[0] = to;
            else owners[1] = to;
        }

        emit OwnershipTransferred(msg.sender, to);
    }

    /// @dev Set a third signer with limited direct Cell powers.
    function setGuardian(address guardian) public payable {
        require(msg.sender == address(this), NotOwner());
        emit OwnershipTransferred(address(this), owners[2] = guardian);
    }

    /// @dev Get message array count between owners.
    function getChatCount() public view returns (uint256) {
        return messages.length;
    }

    /// @dev Chat context with message array by owners.
    function chat(string calldata message) public payable {
        require(
            msg.sender == owners[0] || msg.sender == owners[1] || msg.sender == owners[2],
            NotOwner()
        );
        messages.push(message);
    }

    /// @dev EIP-712 domain separator.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    /// @dev EIP-712 domain computation.
    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("Cell"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /// @dev Receive Cell ETH.
    receive() external payable {}

    /// @dev Receive Cell NFTs.
    function onERC721Received(address, address, uint256, bytes calldata)
        public
        pure
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    /// @dev Receive Cell multitokens.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        public
        pure
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    /// @dev Execute sequence of calls to this Cell contract.
    function multicall(bytes[] calldata data) public payable returns (bytes[] memory retDatas) {
        retDatas = new bytes[](data.length);
        for (uint256 i; i != data.length; ++i) {
            (bool ok, bytes memory ret) = address(this).delegatecall(data[i]);
            if (!ok) _revertWith(ret);
            retDatas[i] = ret;
        }
    }

    /// @dev Bubble up revert errors.
    function _revertWith(bytes memory ret) internal pure {
        assembly ("memory-safe") { revert(add(ret, 0x20), mload(ret)) }
    }
}

error ETHTransferFailed();

function safeTransferETH(address to, uint256 amount) {
    assembly ("memory-safe") {
        if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
            mstore(0x00, 0xb12d13eb)
            revert(0x1c, 0x04)
        }
    }
}

error TransferFailed();

function safeTransfer(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, to)
        mstore(0x34, amount)
        mstore(0x00, 0xa9059cbb000000000000000000000000)
        let success := call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x90b8ec18)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x34, 0)
    }
}

error ApproveFailed();

function safeApprove(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, to)
        mstore(0x34, amount)
        mstore(0x00, 0x095ea7b3000000000000000000000000)
        let success := call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x3e3f8f73)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x34, 0)
    }
}

error TransferFromFailed();

function safeTransferFrom(address token, address from, uint256 amount) {
    assembly ("memory-safe") {
        let m := mload(0x40)
        mstore(0x60, amount)
        mstore(0x40, address())
        mstore(0x2c, shl(96, from))
        mstore(0x0c, 0x23b872dd000000000000000000000000)
        let success := call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x7939f424)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x60, 0)
        mstore(0x40, m)
    }
}

/// @title Cell Wallet Creator (Cell/CellWall.eth)
contract Cells {
    event NewCell(Cell indexed cell);
    mapping(address owner => Cell[]) public cells;

    /// @dev Construct new Cell with initialization calls.
    function createCell(
        address owner0,
        address owner1,
        address guardian,
        bytes32 salt,
        bytes[] calldata initCalls
    ) public payable returns (Cell cell, bool[] memory oks, bytes[] memory retDatas) {
        emit NewCell(cell = new Cell{value: msg.value, salt: salt}(owner0, owner1, guardian));
        cells[owner0].push(cell);
        cells[owner1].push(cell);
        if (guardian != address(0) && guardian != owner0 && guardian != owner1) {
            cells[guardian].push(cell);
        }
        uint256 len = initCalls.length;
        if (len != 0) {
            oks = new bool[](len);
            retDatas = new bytes[](len);
            for (uint256 i; i != len; ++i) {
                (oks[i], retDatas[i]) = address(cell).call(initCalls[i]);
            }
        }
    }
}
