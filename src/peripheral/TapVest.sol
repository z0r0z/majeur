// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title TapVest
/// @notice Singleton for linear vesting from a DAO treasury via the allowance system.
///         DAOs configure a tap by calling `configure()` in an initCall and granting
///         this contract an allowance via `setAllowance(Tap, token, budget)`.
///
///   Vesting formula: owed = ratePerSec * elapsed
///   Claimed = min(owed, allowance, daoBalance)
///   Allowance acts as the total budget cap.
///
///   Setup (include in Summoner initCalls or SafeSummoner extraCalls):
///     1. dao.setAllowance(tap, token, totalBudget)
///     2. tap.configure(token, beneficiary, ratePerSec) // called BY dao -> keyed to msg.sender
///
///   Usage:
///     tap.claim(dao)           // beneficiary claims accrued funds
///     tap.claimable(dao)       // view: how much can be claimed now
///
///   DAO governance:
///     tap.setBeneficiary(newAddr)  // change recipient (dao-only)
///     tap.setRate(newRate)         // change rate, non-retroactive (dao-only)
contract TapVest {
    error NothingToClaim();
    error NotConfigured();
    error ZeroRate();

    event Configured(
        address indexed dao, address indexed beneficiary, address token, uint128 ratePerSec
    );
    event Claimed(address indexed dao, address indexed beneficiary, address token, uint256 amount);
    event BeneficiaryUpdated(address indexed dao, address indexed oldBen, address indexed newBen);
    event RateUpdated(address indexed dao, uint128 oldRate, uint128 newRate);

    struct TapConfig {
        address token; // address(0) = ETH, or ERC20
        address beneficiary; // recipient of vested funds
        uint128 ratePerSec; // smallest-unit/sec (e.g. wei/sec for ETH, 1e-6/sec for USDC)
        uint64 lastClaim; // last claim timestamp
    }

    /// @dev Keyed by DAO address. Set via configure() called by the DAO itself.
    mapping(address dao => TapConfig) public taps;

    /// @notice Configure tap parameters. Must be called by the DAO (e.g. in initCalls).
    /// @param token       Token to vest (address(0) = ETH)
    /// @param beneficiary Recipient of vested funds
    /// @param ratePerSec  Vesting rate in smallest token units per second
    function configure(address token, address beneficiary, uint128 ratePerSec) public {
        if (ratePerSec == 0) revert ZeroRate();
        require(beneficiary != address(0));
        taps[msg.sender] = TapConfig(token, beneficiary, ratePerSec, uint64(block.timestamp));
        emit Configured(msg.sender, beneficiary, token, ratePerSec);
    }

    /// @notice Claim accrued funds. Permissionless — funds always go to the beneficiary.
    /// @param dao The DAO to claim from
    function claim(address dao) public returns (uint256 claimed) {
        TapConfig storage tap = taps[dao];
        if (tap.ratePerSec == 0) revert NotConfigured();

        uint64 elapsed;
        unchecked {
            elapsed = uint64(block.timestamp) - tap.lastClaim;
        }

        uint256 owed = uint256(tap.ratePerSec) * uint256(elapsed);
        if (owed == 0) revert NothingToClaim();

        address token = tap.token;
        address beneficiary = tap.beneficiary;

        // Cap by allowance and DAO balance
        uint256 allowance = IMoloch(dao).allowance(token, address(this));
        uint256 daoBalance = token == address(0) ? dao.balance : balanceOf(token, dao);

        claimed = owed < allowance ? owed : allowance;
        if (claimed > daoBalance) claimed = daoBalance;
        if (claimed == 0) revert NothingToClaim();

        // Update timestamp before external calls (CEI)
        tap.lastClaim = uint64(block.timestamp);

        // Pull from DAO -> this contract
        IMoloch(dao).spendAllowance(token, claimed);

        // Forward to beneficiary
        if (token == address(0)) {
            safeTransferETH(beneficiary, claimed);
        } else {
            safeTransfer(token, beneficiary, claimed);
        }

        emit Claimed(dao, beneficiary, token, claimed);
    }

    /// @notice View: how much can be claimed now.
    function claimable(address dao) public view returns (uint256) {
        TapConfig memory tap = taps[dao];
        if (tap.ratePerSec == 0) return 0;

        uint256 owed;
        unchecked {
            uint64 elapsed = uint64(block.timestamp) - tap.lastClaim;
            owed = uint256(tap.ratePerSec) * uint256(elapsed);
        }
        if (owed == 0) return 0;

        uint256 allowance = IMoloch(dao).allowance(tap.token, address(this));
        uint256 daoBalance = tap.token == address(0) ? dao.balance : balanceOf(tap.token, dao);

        uint256 c = owed < allowance ? owed : allowance;
        if (c > daoBalance) c = daoBalance;
        return c;
    }

    /// @notice View: total owed based on time (ignoring allowance/balance caps).
    function pending(address dao) public view returns (uint256) {
        TapConfig memory tap = taps[dao];
        if (tap.ratePerSec == 0) return 0;
        unchecked {
            uint64 elapsed = uint64(block.timestamp) - tap.lastClaim;
            return uint256(tap.ratePerSec) * uint256(elapsed);
        }
    }

    // ── DAO Governance ──────────────────────────────────────────

    /// @notice Update the beneficiary. Only callable by the DAO.
    function setBeneficiary(address newBeneficiary) public {
        require(newBeneficiary != address(0));
        TapConfig storage tap = taps[msg.sender];
        if (tap.ratePerSec == 0) revert NotConfigured();
        address old = tap.beneficiary;
        tap.beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(msg.sender, old, newBeneficiary);
    }

    /// @notice Update the vesting rate. Non-retroactive: unclaimed time at old rate is
    ///         forfeited, new rate applies from this moment forward. Only callable by the DAO.
    /// @param newRate New rate in smallest units per second. 0 = freeze tap.
    function setRate(uint128 newRate) public {
        TapConfig storage tap = taps[msg.sender];
        if (tap.ratePerSec == 0 && tap.beneficiary == address(0)) revert NotConfigured();
        uint128 oldRate = tap.ratePerSec;
        tap.ratePerSec = newRate;
        tap.lastClaim = uint64(block.timestamp);
        emit RateUpdated(msg.sender, oldRate, newRate);
    }

    /// @dev Accept ETH from DAO via spendAllowance.
    receive() external payable {}

    /// @notice Generate initCalls for setting up a Tap.
    function tapInitCalls(
        address dao,
        address token,
        uint256 budget,
        address beneficiary,
        uint128 ratePerSec
    )
        public
        view
        returns (address target1, bytes memory data1, address target2, bytes memory data2)
    {
        target1 = dao;
        data1 = abi.encodeCall(IMoloch.setAllowance, (address(this), token, budget));
        target2 = address(this);
        data2 = abi.encodeCall(this.configure, (token, beneficiary, ratePerSec));
    }
}

interface IMoloch {
    function spendAllowance(address token, uint256 amount) external;
    function setAllowance(address spender, address token, uint256 amount) external;
    function allowance(address token, address spender) external view returns (uint256);
}

function balanceOf(address token, address account) view returns (uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, account)
        mstore(0x00, 0x70a08231000000000000000000000000)
        amount := mul(
            mload(0x20),
            and(gt(returndatasize(), 0x1f), staticcall(gas(), token, 0x10, 0x24, 0x20, 0x20))
        )
    }
}

function safeTransferETH(address to, uint256 amount) {
    assembly ("memory-safe") {
        if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
            mstore(0x00, 0xb12d13eb)
            revert(0x1c, 0x04)
        }
    }
}

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
