// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

/**
 * @title   Vanilla Option Redeem Token for Strike Tokens
 * @author  Primitive
 */

import { IRedeem } from "../interfaces/IRedeem.sol";
import { ERC20 } from "./ERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

contract Redeem is IRedeem, ERC20 {
    using SafeMath for uint256;

    address public override factory;
    address public override optionToken;
    address public override redeemableToken;

    // solhint-disable-next-line no-empty-blocks
    constructor() public {}

    function initialize(
        address _factory,
        address _optionToken,
        address _redeemableToken
    ) public override {
        require(factory == address(0x0), "ERR_IS_INITIALIZED");
        factory = _factory;
        optionToken = _optionToken;
        redeemableToken = _redeemableToken;
        name = "Primitive Strike Redeem";
        symbol = "REDEEM";
    }

    function mint(address to, uint256 amount) external override {
        require(msg.sender == optionToken, "ERR_NOT_VALID");
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external override {
        require(msg.sender == optionToken, "ERR_NOT_VALID");
        _burn(to, amount);
    }
}
