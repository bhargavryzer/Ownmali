// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOwnmaliEscrow {
    function initialize(address _project, address _admin) external;
    function depositTokens(uint256 amount) external;
    function withdrawTokens(address to, uint256 amount) external;
    function distributeDividends(
        address[] calldata holders,
        uint256[] calldata amounts
    ) external;
    function resolveDispute(
        uint256 orderId,
        bool refundApproved,
        address buyer,
        uint256 amount
    ) external;
    function emergencyWithdraw(address token, address to) external;
    function setProject(address _project) external;
}
