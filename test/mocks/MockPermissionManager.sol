// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract MockPermissionManager {
    mapping(address => mapping(bytes4 => bool)) public permissions;

    function grantPermission(address account, bytes4 functionSelector) external {
        permissions[account][functionSelector] = true;
    }

    function hasPermissions(address account, bytes4 functionSelector) external view returns (bool) {
        return permissions[account][functionSelector];
    }

    function owner() external view returns (address) {
        return msg.sender;
    }
}

