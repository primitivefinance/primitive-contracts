pragma solidity ^0.6.2;

/**
 * @title Primitive's Instrument Controller
 * @author Primitive
 */

import "./ControllerInterface.sol";
import { IPrime } from "../PrimeInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract ControllerMarket is Ownable {
    using SafeMath for uint256;

    struct Initialization {
        bool controllers;
        bool maker;
        bool redeem;
    }

    struct Market {
        address controller;
        uint256 marketId;
        address option;
        address maker;
    }

    struct Controllers {
        address controller;
        address option;
        address pool;
        address redeem;
    }

    Initialization public _isInitialized;
    Controllers public _controllers;
    uint256 public marketNonce;

    mapping(uint256 => Market) public _markets;
    address public _maker;
    address payable[] public makers;

    function initControllers(
        IControllerOption option,
        IControllerPool pool,
        IControllerRedeem redeem
    ) public onlyOwner returns (bool) {
        require(!_isInitialized.controllers, "ERR_INITIALIZED");
        _controllers = Controllers(
            address(this),
            address(option),
            address(pool),
            address(redeem)
        );
        _isInitialized.controllers = true;
        return true;
    }

    /* function initMakerPool(address compoundContract, address oracle) public onlyOwner returns (address) {
        require(!_isInitialized.maker, "ERR_INITIALIZED");
        address maker = _addMarketMaker(compoundContract, oracle);
        _isInitialized.maker = true;
        return maker;
    } */

    function createMaker(
        address oracle,
        string memory name,
        string memory symbol,
        address tokenU,
        address tokenS
    ) public onlyOwner returns (address payable maker) {
        IControllerPool pool = IControllerPool(_controllers.pool);
        maker = pool.addPool(
            oracle,
            name,
            symbol,
            tokenU,
            tokenS
        );
        makers.push(maker);
    }

    function createMarket(
        string memory name,
        string memory symbol,
        address tokenU,
        address tokenS,
        uint256 ratio,
        uint256 expiry
    ) public onlyOwner returns (uint256) {
        IControllerOption optionController = IControllerOption(_controllers.option);

        // Deploys option contract and mints prime erc-721
        (address payable option, uint256 marketId) = optionController.addOption(
            name,
            symbol,
            tokenU,
            tokenS,
            ratio,
            expiry
        );

        // Deploys redeem contract
        IControllerRedeem redeemController = IControllerRedeem(_controllers.redeem);
        address redeem = redeemController.addRedeem(
            "Redeem Primitive Underlying LP",
            "rPULP",
            option,
            tokenS
        );
        optionController.setRedeem(redeem, option);

        // Adds option to pool contract
        IControllerPool pool = IControllerPool(_controllers.pool);
        address payable maker = pool.makerFor(tokenU, tokenS);
        if(maker != address(0)) {
            pool.addMarket(maker, option);
        }

        _markets[marketId] = Market(
            address(this),
            marketId,
            option,
            maker
        );

        return marketId;
    }

    /* function _addMarketMaker(
        address compoundEther,
        address oracle
    ) internal returns (address) {
        IControllerPool pool = IControllerPool(_controllers.pool);
        address poolAddress = pool.addPool(oracle);
        _maker = poolAddress;
        return poolAddress;
    } */

    function getOption(uint256 marketId) public view returns (address) {
        return _markets[marketId].option;
    }

    function getMaker(uint256 marketId) public view returns (address) {
        return _markets[marketId].maker;
    }
}