// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IToken.sol";
import "../interfaces/IUSC.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../common/Mintable.sol";

/// @title USC token contract
contract USC is IUSC, ERC20Permit, ERC20Burnable, Mintable {
  constructor() ERC20("USC", "USC") ERC20Permit("USC") {}

  /// @inheritdoc IToken
  function name() public pure override(IToken, ERC20) returns (string memory) {
    return "USC";
  }

  /// @inheritdoc IToken
  function symbol() public pure override(IToken, ERC20) returns (string memory) {
    return "USC";
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
}
