// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Tin_defi is ERC20, ERC20Burnable, ERC20Snapshot, AccessControl, Pausable, ReentrancyGuard {

    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant TAX_EXCLUDED = keccak256("TAX_EXCLUDED");

    uint256 private tax;
    address private taxWallet;
    uint256 private immutable _cap;

    event taxChanged(uint256 newTax);
    event taxWalletChanged(address newTaxWallet);

    constructor(uint256 _tax, address _taxWallet, uint256 _maxCap) ERC20("Tin Defi", "TIN"){
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        _cap = _maxCap * 10 ** decimals();
        tax = _tax;
        taxWallet = _taxWallet;
    }

    function snapshot() public onlyRole(SNAPSHOT_ROLE) {
        _snapshot();
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(ERC20.totalSupply() + amount <= cap(), "ERC20Capped: cap exceeded");
        _mint(to, amount);
    }

    /** Function Overriden to implement tax on transfer */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        if (!hasRole(TAX_EXCLUDED, sender)) {
            uint256 taxAmount = amount * tax / 100;
            super._transfer(sender, taxWallet, taxAmount);
            amount -= taxAmount;
        }
        super._transfer(sender, recipient, amount);
    }

    /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    function changeTax(uint256 newTax) public onlyRole(DEFAULT_ADMIN_ROLE){
        tax = newTax;
        emit taxChanged(newTax);
    }

    function changeTaxWallet(address newTaxWallet) public onlyRole(DEFAULT_ADMIN_ROLE){
        taxWallet = newTaxWallet;
        emit taxWalletChanged(newTaxWallet);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override(ERC20, ERC20Snapshot)
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}
