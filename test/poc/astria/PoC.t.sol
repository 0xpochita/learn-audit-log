// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/*
 * Isolated reproduction of the Astaria accounting bug.
 * This is a behavioral model, NOT the original Astaria contracts.
 */

contract MockPublicVault {
    uint256 public yIntercept;
    uint256 public slope;
    uint256 public last;

    mapping(uint256 => uint256) public epochData;

    constructor() {
        yIntercept = 100;
        slope = 50;
        last = 1000;
        epochData[1] = 500;
    }
}

contract VulnerableLienToken {
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public payee;

    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
        payee[id] = to;
    }

    // Vulnerable behavior
    // Ownershup changes, but Public Vault accounting is not updated

    function transferFrom(address from, address to, uint256 id) external {
        require(ownerOf[id] == from, "Not Owner");

        ownerOf[id] = to;

        // Missing : 
        // 1. Update Lien Payee 
        // 2. Update PublicVault.yIntercept
        // 3. Update PublicVault.slope
        // 4. Update PublicVault.last 
        // 5. Update PublicVault.epochData
    }
}


contract PoC is Test {
    VulnerableLienToken lienToken;
    MockPublicVault publicVault;

    address privateVault;
    uint256 constant LIEN_ID = 101;

    function setUp() public {
        lienToken = new VulnerableLienToken();
        publicVault = new MockPublicVault();

        privateVault = makeAddr("privateVault");

        lienToken.mint(privateVault, LIEN_ID);
    }

    // forge test --match-test test_PoC_PublicVaultAccountingNotUpdated -vvvv

    function test_PoC_PublicVaultAccountingNotUpdated() public {
        // 1. Record Initial Accounting
        uint256 oldSlope = publicVault.slope();
        uint256 oldIntercept = publicVault.yIntercept();
        uint256 oldLast = publicVault.last();
        uint256 oldEpochData = publicVault.epochData(1);

        // 2. Transfer Lien from private vault to public vault
        vm.prank(privateVault);

        lienToken.transferFrom(privateVault, address(publicVault), LIEN_ID);

        // 3. Verify Ownership successfully transferred
        assertEq(lienToken.ownerOf(LIEN_ID), address(publicVault), "Lien Ownership should transfer");

        // 4. Verify payee is stale
        assertEq(lienToken.payee(LIEN_ID), privateVault, "Payee was not updated");

        // 5. Verify Public Vault accounting is unchanged
        assertEq(publicVault.slope(), oldSlope);
        assertEq(publicVault.yIntercept(), oldIntercept);
        assertEq(publicVault.last(), oldLast);
        assertEq(publicVault.epochData(1), oldEpochData);
    }
}