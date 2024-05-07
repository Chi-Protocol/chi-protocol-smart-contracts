// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/ICHI.sol";
import "../interfaces/IToken.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../common/Mintable.sol";

/// @title CHI token contract
contract CHI is ICHI, ERC20Permit, ERC20Burnable, Mintable {
  constructor(uint256 initialSupply) ERC20("CHI", "CHI") ERC20Permit("CHI") {
    _mint(msg.sender, initialSupply);
  }

  /// @inheritdoc IToken
  function name() public pure override(IToken, ERC20) returns (string memory) {
    return "CHI";
  }

  /// @inheritdoc IToken
  function symbol() public pure override(IToken, ERC20) returns (string memory) {
    return "CHI";
  }

  /// @inheritdoc IToken
  function decimals() public pure override(IToken, ERC20) returns (uint8) {
    return 18;
  }

  /// @inheritdoc IToken
  function mint(address account, uint256 amount) external onlyMinter {
    _mint(account, amount);
  }

  /// @inheritdoc IToken
  function burn(uint256 amount) public override(IToken, ERC20Burnable) onlyMinter {
    super.burn(amount);
  }

  /// @inheritdoc ICHI
  function burnFrom(address account, uint256 amount) public override(ICHI, ERC20Burnable) onlyMinter {
    super.burnFrom(account, amount);
  }
}
