// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOwnmaliOrderManager {
    struct Order {
        address buyer;
        uint256 amount;
        uint256 price;
        uint48 createdAt;
        uint48 cancelRequestedAt;
        bool isFinalized;
        bool isCancelled;
        bool isRefunded;
    }

    function initialize(address _project, address _admin) external;
    function createOrder(address buyer, uint256 amount, uint256 price) external returns (uint256);
    function cancelOrder(uint256 orderId) external;
    function finalizeOrder(uint256 orderId) external;
    function requestRefund(uint256 orderId) external;
    function getOrder(uint256 orderId) external view returns (
        address buyer,
        uint256 amount,
        uint256 price,
        uint48 createdAt,
        uint48 cancelRequestedAt,
        bool isFinalized,
        bool isCancelled,
        bool isRefunded
    );
    function setProject(address _project) external;
}
