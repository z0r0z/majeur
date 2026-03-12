// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IShares {
    function balanceOf(address) external view returns (uint256);
    function burnFromMoloch(address from, uint256 amount) external;
}

interface IMoloch {
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

/// @title ShareBurner
/// @notice Stateless singleton for burning unsold DAO shares after a sale deadline.
///         Both the delegatecall target AND the permit spender — one contract, one address.
///
///   Setup (include in DAICO customCalls or Summoner initCalls):
///     Use permitCall() to generate the setPermit init call, or encode manually:
///     dao.setPermit(1, burner, 0, burnData, salt, burner, 1)
///
///   After deadline:
///     burner.closeSale(dao, shares, deadline, salt)
contract ShareBurner {
    error SaleActive();

    event SaleClosed(address indexed dao, uint256 sharesBurned);

    /// @notice Delegatecall entry — runs in DAO context (address(this) = DAO).
    ///         Burns all shares held by the DAO after deadline. Payable to
    ///         skip msg.value check in delegatecall.
    function burnUnsold(address shares, uint256 deadline) public payable {
        if (block.timestamp <= deadline) revert SaleActive();
        uint256 bal = IShares(shares).balanceOf(address(this));
        if (bal != 0) IShares(shares).burnFromMoloch(address(this), bal);
    }

    /// @notice Burn unsold DAO shares. Fully permissionless — deadline is
    ///         enforced inside burnUnsold's delegatecall. One-shot (permit
    ///         count=1), so second call reverts in Moloch.
    function closeSale(address dao, address shares, uint256 deadline, bytes32 nonce) public {
        uint256 bal = IShares(shares).balanceOf(dao);
        IMoloch(dao)
            .spendPermit(
                1,
                address(this),
                0,
                abi.encodeWithSelector(this.burnUnsold.selector, shares, deadline),
                nonce
            );
        emit SaleClosed(dao, bal);
    }

    /*//////////////////////////////////////////////////////////////
                          PERMIT HELPER
    //////////////////////////////////////////////////////////////*/

    /// @notice Generate the setPermit Call for inclusion in init/custom calls.
    ///         Spender = this contract. Count = 1 (one-shot).
    function permitCall(address dao, address shares, uint256 deadline, bytes32 salt)
        public
        view
        returns (address, uint256, bytes memory)
    {
        bytes memory burnData = abi.encodeWithSelector(this.burnUnsold.selector, shares, deadline);

        return (
            dao,
            0,
            abi.encodeWithSelector(
                IMoloch.setPermit.selector,
                uint8(1), // op = delegatecall
                address(this), // target = this contract
                uint256(0), // value = 0
                burnData, // encoded burnUnsold call
                salt, // nonce
                address(this), // spender = this contract
                uint256(1) // count = 1 (one-shot)
            )
        );
    }
}
