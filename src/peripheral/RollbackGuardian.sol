// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct Call {
    address target;
    uint256 value;
    bytes data;
}

interface IMoloch {
    function bumpConfig() external;
    function setAutoFutarchy(uint256 param, uint256 cap) external;
    function spendPermit(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
        external;
    function setPermit(
        uint8 op,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32 nonce,
        address spender,
        uint256 count
    ) external;
}

/// @title RollbackGuardian
/// @notice Singleton that lets a designated guardian emergency-bump a DAO's config,
///         invalidating all pending proposals and preventing malicious execution.
///
///   The guardian holds a pre-authorized permit to call `bumpConfig()` on the DAO.
///   After one bump, the config change invalidates the permit itself (config is part
///   of the permit ID hash), making this inherently one-shot. The DAO must re-authorize
///   via governance to restore the guardian's power.
///
///   Setup (include in Summoner initCalls or SafeSummoner extraCalls):
///     1. rollbackGuardian.configure(guardian, expiry)
///     2. dao.setPermit(0, dao, 0, bumpConfig(), "rollback", rollbackGuardian, 1)
///     Or use permitCall() / initCalls() helpers to generate both.
///
///   Emergency use:
///     rollbackGuardian.rollback(dao)        // nuclear: bump config, orphan all proposals
///     rollbackGuardian.killFutarchy(dao)    // lighter: disable auto-futarchy earmarks
///
///   DAO governance:
///     rollbackGuardian.setGuardian(newGuardian)  // rotate guardian
///     rollbackGuardian.setExpiry(newExpiry)       // extend or shorten window
///     rollbackGuardian.revoke()                   // remove guardian entirely
contract RollbackGuardian {
    error Expired();
    error Unauthorized();
    error NotConfigured();

    event Configured(address indexed dao, address guardian, uint40 expiry);
    event Rolled(address indexed dao, address guardian);
    event FutarchyKilled(address indexed dao, address guardian);
    event GuardianUpdated(address indexed dao, address oldGuardian, address newGuardian);
    event ExpiryUpdated(address indexed dao, uint40 oldExpiry, uint40 newExpiry);
    event Revoked(address indexed dao);

    struct Config {
        address guardian;
        uint40 expiry; // unix timestamp, 0 = no expiry
    }

    mapping(address dao => Config) public configs;

    bytes32 public constant NONCE = keccak256("RollbackGuardian");
    bytes32 public constant FUTARCHY_NONCE = keccak256("RollbackGuardian.killFutarchy");

    /// @notice Configure the guardian. Called by the DAO in initCalls.
    function configure(address guardian, uint40 expiry) public {
        if (guardian == address(0)) revert Unauthorized();
        configs[msg.sender] = Config(guardian, expiry);
        emit Configured(msg.sender, guardian, expiry);
    }

    /// @notice Emergency config bump. Callable only by the guardian, before expiry.
    ///         Spends the pre-authorized permit to call dao.bumpConfig().
    ///         Inherently one-shot: the config bump invalidates the permit ID.
    function rollback(address dao) public {
        Config memory c = configs[dao];
        if (c.guardian == address(0)) revert NotConfigured();
        if (msg.sender != c.guardian) revert Unauthorized();
        if (c.expiry != 0 && block.timestamp > c.expiry) revert Expired();

        IMoloch(dao)
            .spendPermit(
                0, // op = call
                dao, // target = DAO itself
                0, // value = 0
                abi.encodeCall(IMoloch.bumpConfig, ()), // data
                NONCE
            );

        emit Rolled(dao, msg.sender);
    }

    /// @notice Disable auto-futarchy. Lighter alternative to rollback — stops
    ///         NO-coalition futarchy reward farming without invalidating all proposals.
    ///         Inherently one-shot: the DAO must re-authorize via governance.
    function killFutarchy(address dao) public {
        Config memory c = configs[dao];
        if (c.guardian == address(0)) revert NotConfigured();
        if (msg.sender != c.guardian) revert Unauthorized();
        if (c.expiry != 0 && block.timestamp > c.expiry) revert Expired();

        IMoloch(dao)
            .spendPermit(
                0, // op = call
                dao, // target = DAO itself
                0, // value = 0
                abi.encodeCall(IMoloch.setAutoFutarchy, (0, 0)), // disable futarchy
                FUTARCHY_NONCE
            );

        emit FutarchyKilled(dao, msg.sender);
    }

    // ── DAO Governance ──────────────────────────────────────────

    /// @notice Replace the guardian. Only callable by the DAO.
    function setGuardian(address newGuardian) public {
        Config storage c = configs[msg.sender];
        if (c.guardian == address(0)) revert NotConfigured();
        if (newGuardian == address(0)) revert Unauthorized();
        address old = c.guardian;
        c.guardian = newGuardian;
        emit GuardianUpdated(msg.sender, old, newGuardian);
    }

    /// @notice Update the expiry. Only callable by the DAO.
    function setExpiry(uint40 newExpiry) public {
        Config storage c = configs[msg.sender];
        if (c.guardian == address(0)) revert NotConfigured();
        uint40 old = c.expiry;
        c.expiry = newExpiry;
        emit ExpiryUpdated(msg.sender, old, newExpiry);
    }

    /// @notice Remove the guardian entirely. Only callable by the DAO.
    function revoke() public {
        if (configs[msg.sender].guardian == address(0)) revert NotConfigured();
        delete configs[msg.sender];
        emit Revoked(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                          INIT CALL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Generate the setPermit call for bumpConfig authorization.
    function rollbackPermitCall(address dao)
        public
        view
        returns (address target, uint256 value, bytes memory data)
    {
        target = dao;
        value = 0;
        data = abi.encodeCall(
            IMoloch.setPermit,
            (
                uint8(0), // op = call
                dao, // target = DAO itself
                uint256(0), // value = 0
                abi.encodeCall(IMoloch.bumpConfig, ()), // bumpConfig calldata
                NONCE, // nonce
                address(this), // spender = this contract
                uint256(1) // count = 1
            )
        );
    }

    /// @notice Generate the setPermit call for killFutarchy authorization.
    function futarchyPermitCall(address dao)
        public
        view
        returns (address target, uint256 value, bytes memory data)
    {
        target = dao;
        value = 0;
        data = abi.encodeCall(
            IMoloch.setPermit,
            (
                uint8(0),
                dao,
                uint256(0),
                abi.encodeCall(IMoloch.setAutoFutarchy, (0, 0)),
                FUTARCHY_NONCE,
                address(this),
                uint256(1)
            )
        );
    }

    /// @notice Generate all initCalls: configure + rollback permit + futarchy permit.
    function initCalls(address dao, address guardian, uint40 expiry)
        public
        view
        returns (Call[3] memory calls)
    {
        calls[0] = Call(address(this), 0, abi.encodeCall(this.configure, (guardian, expiry)));
        (,, bytes memory d1) = rollbackPermitCall(dao);
        calls[1] = Call(dao, 0, d1);
        (,, bytes memory d2) = futarchyPermitCall(dao);
        calls[2] = Call(dao, 0, d2);
    }
}
