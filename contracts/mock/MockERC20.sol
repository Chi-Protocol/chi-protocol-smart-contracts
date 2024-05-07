// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
  constructor(string memory _name, string memory _symbol, uint256 initialSupply) ERC20(_name, _symbol) {
    _mint(msg.sender, initialSupply);
  }

  function burnFrom(address account, uint256 amount) public {
    _burn(account, amount);
  }
}
